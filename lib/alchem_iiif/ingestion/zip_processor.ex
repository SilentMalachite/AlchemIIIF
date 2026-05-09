defmodule AlchemIiif.Ingestion.ZipProcessor do
  @moduledoc """
  ZIP アーカイブから PNG ページ画像を安全に展開するモジュール。

  ## 戻り値

  `PdfProcessor.convert_to_images/3` と互換の形:
  `{:ok, %{page_count: pos_integer(), image_paths: [String.t()]}}` または `{:error, term()}`。

  ## セキュリティ

  - Zip Slip: `Path.safe_relative/1` と絶対パス拒否で防御
  - 拡張子偽装: PNG マジックバイト（`<<137, 80, 78, 71, 13, 10, 26, 10>>`）を検証
  - Zip bomb: `:zip.list_dir/1` で得る宣言サイズ合計を事前検証
  - DoS: PNG エントリ数を `max_pages` で制限
  - シンボリックリンク: 展開後 `File.lstat!` で `:regular` のみ採用

  ## 命名

  自然順ソート後の出現順に `page-001-<timestamp>.png`, `page-002-<timestamp>.png`, ... と
  振り直す。`<timestamp>` はジョブ開始時の `System.system_time(:millisecond)`。
  """

  require Logger

  @png_magic <<137, 80, 78, 71, 13, 10, 26, 10>>
  @default_max_pages 200
  @default_max_extracted_bytes 2 * 1024 * 1024 * 1024

  @spec extract_pngs(String.t(), String.t(), map()) ::
          {:ok, %{page_count: pos_integer(), image_paths: [String.t()]}}
          | {:error, term()}
  def extract_pngs(zip_path, output_dir, opts \\ %{}) do
    File.mkdir_p!(output_dir)

    with {:ok, entries} <- list_entries(zip_path),
         {:ok, accepted} <- filter_and_validate(entries, opts) do
      timestamp = System.system_time(:millisecond)
      extract_and_normalize(zip_path, output_dir, accepted, timestamp)
    end
  end

  # --- private ---

  defp list_entries(zip_path) do
    case :zip.list_dir(String.to_charlist(zip_path)) do
      {:ok, list} -> {:ok, list}
      {:error, reason} -> {:error, {:zip_list_failed, reason}}
    end
  end

  # PNG ファイルだけ拾い、危険なエントリを弾く。
  # 戻り値: {:ok, [{relative_path :: String.t(), uncompressed_size :: non_neg_integer()}]}
  defp filter_and_validate(entries, opts) do
    max_pages = Map.get(opts, :max_pages, @default_max_pages)
    max_bytes = Map.get(opts, :max_extracted_bytes, @default_max_extracted_bytes)

    candidates =
      entries
      |> Enum.flat_map(&entry_to_candidate/1)
      |> Enum.sort_by(fn {path, _size} -> natural_sort_key(path) end)

    cond do
      candidates == [] ->
        {:error, :no_png_entries}

      length(candidates) > max_pages ->
        {:error, {:too_many_pages, length(candidates), max_pages}}

      Enum.sum(Enum.map(candidates, &elem(&1, 1))) > max_bytes ->
        {:error, :extracted_size_exceeds_limit}

      true ->
        {:ok, candidates}
    end
  end

  # `:zip.list_dir/1` の各要素を {path, size} に正規化。
  # 危険なものは候補から外す。ディレクトリは無視。
  defp entry_to_candidate({:zip_file, name, info, _comment, _offset, _comp_size}) do
    path = to_string(name)
    # :file_info レコードの第 2 要素（index 1）が展開後バイトサイズ
    size = elem(info, 1)

    cond do
      String.ends_with?(path, "/") -> []
      not png_extension?(path) -> []
      not safe_relative?(path) -> []
      true -> [{path, size}]
    end
  end

  defp entry_to_candidate(_), do: []

  defp png_extension?(path), do: String.downcase(Path.extname(path)) == ".png"

  defp safe_relative?(path) do
    Path.type(path) == :relative and Path.safe_relative(path) != :error
  end

  defp extract_and_normalize(zip_path, output_dir, accepted, timestamp) do
    file_list = Enum.map(accepted, fn {p, _} -> String.to_charlist(p) end)

    case :zip.unzip(
           String.to_charlist(zip_path),
           [{:cwd, String.to_charlist(output_dir)}, {:file_list, file_list}]
         ) do
      {:ok, extracted} ->
        finalize_extracted(extracted, output_dir, timestamp)

      {:error, reason} ->
        {:error, {:zip_unzip_failed, reason}}
    end
  end

  # 展開済み実ファイルから PNG マジックバイト・regular file を満たすものを採用し、
  # 連番リネームする。失敗エントリは個別に削除して結果から除外。
  defp finalize_extracted(extracted_charlists, output_dir, timestamp) do
    extracted_paths = Enum.map(extracted_charlists, &to_string/1)

    accepted_paths =
      extracted_paths
      |> Enum.sort_by(&natural_sort_key/1)
      |> Enum.filter(&regular_png?/1)

    rejected = extracted_paths -- accepted_paths

    Enum.each(rejected, fn path ->
      Logger.warning("[ZipProcessor] rejecting non-PNG or non-regular entry: #{path}")
      File.rm(path)
    end)

    case rename_to_pages(accepted_paths, output_dir, timestamp) do
      [] -> {:error, :no_valid_png}
      renamed -> {:ok, %{page_count: length(renamed), image_paths: renamed}}
    end
  end

  defp regular_png?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> png_magic_bytes?(path)
      _ -> false
    end
  end

  defp png_magic_bytes?(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 8)) do
      {:ok, @png_magic} -> true
      _ -> false
    end
  end

  defp rename_to_pages(paths, output_dir, timestamp) do
    paths
    |> Enum.with_index(1)
    |> Enum.map(fn {original, idx} ->
      target =
        Path.join(
          output_dir,
          IO.iodata_to_binary(:io_lib.format("page-~3..0B-~B.png", [idx, timestamp]))
        )

      File.rename!(original, target)
      target
    end)
  end

  @doc false
  # `p1.png, p2.png, p10.png` を安定して順序付ける自然順ソートキー。
  # 数値部は `{0, integer}`、非数値部は `{1, string}` のタプル列で表現する。
  # `Regex.scan` は一致したグループのみ返す（非一致グループは省略される）ため、
  # 要素数で数値／非数値を判別する。
  def natural_sort_key(path) do
    Regex.scan(~r/(\d+)|(\D+)/, path)
    |> Enum.map(fn
      # 数値グループが一致 → [full_match, digits]（要素数 2）
      [_, num] -> {0, String.to_integer(num)}
      # 非数値グループが一致 → [full_match, "", str]（要素数 3）
      [_, "", str] -> {1, str}
    end)
  end
end
