defmodule AlchemIiif.Ingestion.PdfProcessor do
  require Logger

  @moduledoc """
  pdftoppm を使用して PDF ページを高解像度 PNG 画像に変換するモジュール。

  ## なぜこの設計か

  - **pdftoppm を採用**: Poppler スイートの一部であり、フォント埋め込みや
    日本語レンダリングに優れています。ImageMagick の `convert` コマンドと
    比較して、PDF 処理に特化しており出力品質が安定しています。
  - **300 DPI**: 学術資料（特に線画）の品質を確保するため 300 DPI を
    使用しています。処理速度の最適化は application.ex 側の Vix 設定
    （スレッド数・キャッシュ制限）で対応しています。
  - **チャンク逐次処理**: 2GB RAM の VPS でも安全に動作するよう、
    10 ページ単位でチャンク分割し `max_concurrency: 1` で逐次実行します。
    これにより、任意の時点での最大メモリ使用量を制限できます。
  """

  # OOM 防止のためのチャンクサイズ（2GB RAM VPS 向け）
  @chunk_size 10
  @default_max_pages 200
  @default_command_timeout_ms 120_000
  @default_chunk_timeout_ms 125_000

  @doc """
  PDFファイルの全ページを PNG に変換します。
  出力ディレクトリに page-001-{timestamp}.png, page-002-{timestamp}.png ... の形式で保存されます。
  タイムスタンプにより、再アップロード時にブラウザキャッシュを自動的にバイパスします。

  大規模 PDF（200+ ページ）でも OOM を起こさないよう、10 ページ単位のチャンクに
  分割して逐次処理します。

  ## 引数
    - pdf_path: PDF ファイルのパス
    - output_dir: 出力先ディレクトリ

  ## 戻り値
    - {:ok, %{page_count: integer, image_paths: [String.t()]}}
    - {:error, reason}
  """
  def convert_to_images(pdf_path, output_dir, opts \\ %{}) do
    # セキュリティ注記: output_dir は内部生成パス（priv/uploads/pages/{id}）、
    # cmd は固定文字列 "pdftoppm" — 外部入力由来ではないため安全。
    File.mkdir_p!(output_dir)

    abs_pdf_path = Path.expand(pdf_path)
    abs_output_prefix = Path.expand(Path.join(output_dir, "page"))

    # まずページ数を取得し、上限を超える PDF は変換前に止める。
    case get_page_count(abs_pdf_path, opts) do
      {:ok, total_pages} ->
        with :ok <- validate_page_count(total_pages, opts) do
          run_chunked_conversion(abs_pdf_path, abs_output_prefix, output_dir, total_pages, opts)
        end

      {:error, reason} ->
        Logger.error("[PdfProcessor] Command failed with exit code (pdfinfo): #{reason}")

        {:error, "PDF変換に失敗しました (pdfinfo): #{reason}"}
    end
  end

  @doc """
  PDFのページ数を取得します。
  """
  def get_page_count(pdf_path, opts \\ %{}) do
    case run_command(
           "pdfinfo",
           [pdf_path],
           option(opts, :command_timeout_ms, @default_command_timeout_ms)
         ) do
      {:ok, {output, 0}} ->
        case Regex.run(~r/Pages:\s+(\d+)/, output) do
          [_, count] -> {:ok, String.to_integer(count)}
          _ -> {:error, "ページ数を取得できませんでした"}
        end

      {:ok, {_error, _}} ->
        {:error, "PDF情報の取得に失敗しました"}

      {:error, :timeout} ->
        Logger.error("[PdfProcessor] pdfinfo timed out")
        {:error, "PDF情報の取得がタイムアウトしました"}
    end
  end

  # --- Private Functions ---

  defp validate_page_count(total_pages, opts) do
    max_pages = option(opts, :max_pages, @default_max_pages)

    if total_pages <= max_pages do
      :ok
    else
      Logger.warning(
        "[PdfProcessor] PDF page count #{total_pages} exceeds page limit #{max_pages}"
      )

      {:error, "PDFページ数の上限（#{max_pages}ページ）を超えています"}
    end
  end

  # チャンク逐次処理の実行
  defp run_chunked_conversion(abs_pdf_path, abs_output_prefix, output_dir, total_pages, opts) do
    chunks = build_chunks(total_pages)

    Logger.info(
      "[PdfProcessor] Processing #{total_pages} pages in #{length(chunks)} chunks of #{@chunk_size}"
    )

    try do
      # max_concurrency: 1 で逐次実行（OOM 防止の要）
      results =
        chunks
        |> Task.async_stream(
          fn {first, last} ->
            result = run_pdftoppm_chunk(abs_pdf_path, abs_output_prefix, first, last, opts)

            # チャンク完了ごとに進捗をブロードキャスト（UI プログレスバー用）
            if result == :ok do
              broadcast_chunk_progress(last, total_pages, opts)
            end

            result
          end,
          max_concurrency: 1,
          timeout: option(opts, :chunk_timeout_ms, @default_chunk_timeout_ms),
          on_timeout: :kill_task,
          ordered: true
        )
        |> Enum.to_list()

      # チャンク処理結果を検証
      case find_chunk_error(results) do
        nil ->
          collect_and_rename_images(output_dir)

        error ->
          error
      end
    rescue
      e in ErlangError ->
        handle_erlang_error(e)
    end
  end

  # ページ範囲をチャンクに分割（例: 25ページ → [{1,10}, {11,20}, {21,25}]）
  defp build_chunks(total_pages) do
    1..total_pages
    |> Enum.chunk_every(@chunk_size)
    |> Enum.map(fn chunk ->
      {List.first(chunk), List.last(chunk)}
    end)
  end

  # 1チャンク分の pdftoppm 実行
  defp run_pdftoppm_chunk(abs_pdf_path, abs_output_prefix, first_page, last_page, opts) do
    cmd = "pdftoppm"
    color_mode = option(opts, :color_mode, "mono")

    # カラーモードに応じてフラグを構築
    # "mono" → -gray（グレースケール変換で高速化）
    # "color" → フラグなし（フルカラー出力）
    gray_flag = if color_mode == "mono", do: ["-gray"], else: []

    args =
      gray_flag ++
        [
          "-png",
          "-r",
          "300",
          "-f",
          Integer.to_string(first_page),
          "-l",
          Integer.to_string(last_page),
          abs_pdf_path,
          abs_output_prefix
        ]

    Logger.info("[PdfProcessor] Chunk: pages #{first_page}-#{last_page}")

    case run_command(cmd, args, option(opts, :command_timeout_ms, @default_command_timeout_ms)) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {error_output, exit_code}} ->
        Logger.error(
          "[PdfProcessor] Chunk failed (pages #{first_page}-#{last_page}), " <>
            "exit code #{exit_code}: #{error_output}"
        )

        {:error, "PDF変換に失敗しました (exit code #{exit_code}): #{error_output}"}

      {:error, :timeout} ->
        Logger.error("[PdfProcessor] Chunk timed out (pages #{first_page}-#{last_page})")
        {:error, "PDF変換がタイムアウトしました"}
    end
  end

  # チャンク結果からエラーを探す
  defp find_chunk_error(results) do
    Enum.find_value(results, fn
      {:ok, :ok} -> nil
      {:ok, {:error, _} = error} -> error
      {:exit, :timeout} -> {:error, "PDF変換がタイムアウトしました"}
      {:exit, reason} -> {:error, "チャンク処理が異常終了しました: #{inspect(reason)}"}
    end)
  end

  # 生成された PNG をソートしてタイムスタンプ付きリネーム
  defp collect_and_rename_images(output_dir) do
    timestamp = System.system_time(:second)

    # Path.wildcard で確実に収集し、明示的にソート
    image_paths =
      Path.wildcard(Path.join(output_dir, "page*.png"))
      |> Enum.sort()
      |> Enum.map(fn original_path ->
        original_name = Path.basename(original_path)
        # page-01.png → page-01-1708065543.png
        versioned_name = String.replace(original_name, ~r/\.png$/, "-#{timestamp}.png")
        versioned_path = Path.join(output_dir, versioned_name)
        File.rename!(original_path, versioned_path)
        versioned_path
      end)

    if Enum.empty?(image_paths) do
      Logger.error("[PdfProcessor] No images generated despite successful conversion")
      {:error, "画像が生成されませんでした (exit code 0)"}
    else
      Logger.info("[PdfProcessor] Successfully generated #{length(image_paths)} images")
      {:ok, %{page_count: length(image_paths), image_paths: image_paths}}
    end
  end

  # チャンク完了時の進捗ブロードキャスト（user_id が opts に含まれる場合のみ）
  defp broadcast_chunk_progress(current_page, total_pages, %{user_id: user_id})
       when not is_nil(user_id) do
    Phoenix.PubSub.broadcast(
      AlchemIiif.PubSub,
      "pdf_pipeline:#{user_id}",
      {:extraction_progress, current_page, total_pages}
    )
  end

  defp broadcast_chunk_progress(_current_page, _total_pages, _opts), do: :ok

  # ErlangError ハンドリング（enoent 対応）
  defp handle_erlang_error(e) do
    if e.original == :enoent do
      Logger.error("[PdfProcessor] pdftoppm not found")

      {:error, "pdftoppm コマンドが見つかりません。Poppler がインストールされているか確認してください。"}
    else
      Logger.error("[PdfProcessor] System error: #{inspect(e)}")
      {:error, "システムエラーが発生しました: #{inspect(e)}"}
    end
  end

  defp run_command(cmd, args, timeout_ms) do
    task = Task.async(fn -> System.cmd(cmd, args, stderr_to_stdout: true) end)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        {:ok, result}

      {:exit, {%ErlangError{} = error, _stacktrace}} ->
        raise error

      {:exit, reason} ->
        {:error, reason}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp option(opts, key, default) do
    value =
      cond do
        is_map(opts) -> Map.get(opts, key)
        Keyword.keyword?(opts) -> Keyword.get(opts, key)
        true -> nil
      end

    if is_nil(value), do: config_default(key, default), else: value
  end

  defp config_default(:max_pages, default),
    do: Application.get_env(:alchem_iiif, :pdf_max_pages, default)

  defp config_default(:command_timeout_ms, default),
    do: Application.get_env(:alchem_iiif, :pdf_command_timeout_ms, default)

  defp config_default(:chunk_timeout_ms, default),
    do: Application.get_env(:alchem_iiif, :pdf_chunk_timeout_ms, default)

  defp config_default(_key, default), do: default
end
