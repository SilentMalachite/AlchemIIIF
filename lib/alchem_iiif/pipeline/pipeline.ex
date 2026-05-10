defmodule AlchemIiif.Pipeline do
  @moduledoc """
  リソース認識型並列処理パイプラインのオーケストレーションモジュール。

  Task.async_stream を使用して PDF 抽出・PTIF 変換を並列化し、
  PubSub でリアルタイム進捗をブロードキャストします。

  ## なぜこの設計か

  - **Task.async_stream**: GenStage や Broadway と比較して、バッチ処理には
    Task.async_stream がシンプルで適しています。考古学資料のバッチサイズは
    通常数十〜数百件のため、バックプレッシャー制御よりも簡潔さを優先しました。
  - **PubSub リアルタイム進捗**: PTIF 生成は1件あたり数秒〜数十秒かかるため、
    ユーザーに「処理が進んでいる」フィードバックを返すことが認知的に重要です。
    LiveView の PubSub 統合により、サーバープッシュで即座に UI を更新します。
  - **ResourceMonitor 連携**: 同時実行数を動的に制限することで、メモリ不足による
    OOM Kill を防ぎつつ、利用可能なリソースを最大限活用します。
  """
  require Logger

  alias AlchemIiif.Iiif.Manifest
  alias AlchemIiif.Ingestion
  alias AlchemIiif.Ingestion.{ImageProcessor, PdfProcessor, PdfSource}
  alias AlchemIiif.Pipeline.ResourceMonitor
  alias AlchemIiif.Repo
  alias AlchemIiif.UploadStore
  alias Phoenix.PubSub

  @pubsub AlchemIiif.PubSub

  # --- 公開 API ---

  @doc """
  パイプラインの PubSub トピック名を返します。
  """
  def topic(pipeline_id), do: "pipeline:#{pipeline_id}"

  @doc """
  PDF パイプラインのユーザー通知トピック名を返します。
  バックグラウンド処理完了時に LiveView へ画面遷移を通知するために使用します。
  """
  def pdf_pipeline_topic(user_id), do: "pdf_pipeline:#{user_id}"

  @doc """
  互換用ラッパ。`source.source_type == "pdf"` 想定の旧呼び出し経路を維持する。
  内部では `run_extraction/4` に委譲する。
  """
  def run_pdf_extraction(pdf_source, pdf_path, pipeline_id, opts \\ %{}) do
    source = Map.put_new(pdf_source, :source_type, "pdf")
    run_extraction(source, pdf_path, pipeline_id, opts)
  end

  @doc """
  ソース（PDF/ZIP）から PNG を抽出し、ExtractedImage を一括登録する。

  source.source_type で `PdfProcessor` / `ZipProcessor` を分岐する。
  """
  def run_extraction(source, source_path, pipeline_id, opts \\ %{}) do
    broadcast_progress(pipeline_id, %{
      event: :pipeline_started,
      phase: :extraction,
      message: extraction_start_message(source)
    })

    job_id = Ecto.UUID.generate()
    tmp_dir = Path.join(System.tmp_dir!(), "alchemiiif_job_#{job_id}")
    output_dir = UploadStore.pages_dir(source.id)
    File.mkdir_p!(output_dir)

    Logger.info(
      "[Pipeline] extraction started: type=#{source.source_type} #{source_path} -> tmp:#{tmp_dir} -> #{output_dir}"
    )

    try do
      case run_processor(source, source_path, tmp_dir, opts) do
        {:ok, %{page_count: page_count, image_paths: tmp_image_paths}} ->
          finalize_extraction(source, tmp_image_paths, page_count, output_dir, pipeline_id, opts)

        {:error, reason} ->
          handle_extraction_error(source, reason, pipeline_id)
      end
    catch
      {:pipeline_abort, reason} -> {:error, reason}
    after
      File.rm_rf(tmp_dir)
      Logger.info("[Pipeline] Cleaned up temp directory: #{tmp_dir}")

      if PdfSource.zip?(source) do
        File.rm(source_path)
        Logger.info("[Pipeline] Cleaned up zip source: #{source_path}")
      end
    end
  end

  defp extraction_start_message(%{source_type: "zip"}), do: "ZIP の展開を開始します..."
  defp extraction_start_message(_), do: "PDF変換を開始します..."

  defp run_processor(%{source_type: "pdf"} = _source, source_path, tmp_dir, opts) do
    processor_opts = %{
      user_id: opts[:owner_id],
      color_mode: opts[:color_mode] || "mono",
      max_pages: opts[:max_pages]
    }

    PdfProcessor.convert_to_images(source_path, tmp_dir, processor_opts)
  end

  defp run_processor(%{source_type: "zip"} = _source, source_path, tmp_dir, opts) do
    base = if max = opts[:max_pages], do: %{max_pages: max}, else: %{}

    processor_opts =
      case Application.get_env(:alchem_iiif, AlchemIiif.Ingestion.ZipProcessor, []) do
        [] -> base
        kw -> Map.merge(Map.new(kw), base)
      end

    AlchemIiif.Ingestion.ZipProcessor.extract_pngs(source_path, tmp_dir, processor_opts)
  end

  defp finalize_extraction(source, tmp_image_paths, page_count, output_dir, pipeline_id, opts) do
    image_paths =
      Enum.map(tmp_image_paths, fn tmp_path ->
        filename = Path.basename(tmp_path)
        final_path = Path.join(output_dir, filename)
        File.cp!(tmp_path, final_path)
        final_path
      end)

    case update_pdf_source_if_present(source.id, %{page_count: page_count, status: "ready"}) do
      {:ok, _} ->
        :ok

      {:error, :not_found} ->
        Logger.warning("[Pipeline] PdfSource #{source.id} disappeared before ready update")
        throw({:pipeline_abort, :pdf_source_not_found})

      {:error, error} ->
        Logger.warning("[Pipeline] Failed to update PdfSource #{source.id}: #{inspect(error)}")
        throw({:pipeline_abort, :pdf_source_update_failed})
    end

    broadcast_progress(pipeline_id, %{
      event: :phase_complete,
      phase: :extraction,
      message: "抽出完了: #{page_count}ページ",
      total: page_count
    })

    attrs_list =
      image_paths
      |> Enum.with_index(1)
      |> Enum.map(fn {image_path, page_number} ->
        %{
          pdf_source_id: source.id,
          page_number: page_number,
          image_path: image_path
        }
        |> maybe_put_owner_id(opts)
      end)

    {_count, images} = Ingestion.bulk_create_extracted_images(attrs_list)

    Enum.each(Enum.with_index(images, 1), fn {_image, page_number} ->
      broadcast_progress(pipeline_id, %{
        event: :task_progress,
        task_id: "page-#{page_number}",
        status: :completed,
        progress: round(page_number / page_count * 100),
        message: "ページ #{page_number} を登録しました"
      })
    end)

    broadcast_progress(pipeline_id, %{
      event: :pipeline_complete,
      phase: :extraction,
      total: page_count,
      succeeded: length(images),
      failed: 0,
      pdf_source_id: source.id
    })

    if owner_id = opts[:owner_id] do
      PubSub.broadcast(
        @pubsub,
        pdf_pipeline_topic(owner_id),
        {:extraction_complete, source.id}
      )
    end

    {:ok, %{page_count: page_count, images: images}}
  end

  defp handle_extraction_error(source, reason, pipeline_id) do
    case update_pdf_source_if_present(source.id, %{status: "error"}) do
      {:ok, _} ->
        :ok

      {:error, :not_found} ->
        Logger.warning("[Pipeline] PdfSource #{source.id} disappeared before error update")

      {:error, error} ->
        Logger.warning(
          "[Pipeline] Failed to mark PdfSource #{source.id} as error: #{inspect(error)}"
        )
    end

    broadcast_progress(pipeline_id, %{
      event: :pipeline_error,
      phase: :extraction,
      message: "抽出に失敗しました: #{reason}"
    })

    {:error, reason}
  end

  @doc """
  複数画像の PTIF 生成を並列で実行します（メモリガード付き）。

  ## 引数
    - extracted_images: ExtractedImage レコードのリスト
    - pipeline_id: パイプライン識別子

  ## 戻り値
    - {:ok, %{total: integer, succeeded: integer, failed: integer, results: list}}
  """
  def run_ptif_generation(extracted_images, pipeline_id) do
    total = length(extracted_images)
    # メモリガードで同時実行数を制限
    max_workers = ResourceMonitor.max_ptif_workers()

    Logger.info("[Pipeline] PTIF生成開始: #{total}件, 最大同時実行数: #{max_workers}")

    broadcast_progress(pipeline_id, %{
      event: :pipeline_started,
      phase: :ptif_generation,
      message: "PTIF生成を開始します（#{total}件, 並列度: #{max_workers}）...",
      total: total
    })

    results =
      extracted_images
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {image, index} ->
          task_id = "ptif-#{image.id}"

          broadcast_progress(pipeline_id, %{
            event: :task_progress,
            task_id: task_id,
            status: :processing,
            progress: 0,
            message: "PTIF生成中: ページ #{image.page_number}"
          })

          result = generate_single_ptif(image)

          case result do
            {:ok, _updated_image} ->
              broadcast_progress(pipeline_id, %{
                event: :task_progress,
                task_id: task_id,
                status: :completed,
                progress: round(index / total * 100),
                message: "PTIF生成完了: ページ #{image.page_number}"
              })

            {:error, reason} ->
              broadcast_progress(pipeline_id, %{
                event: :task_progress,
                task_id: task_id,
                status: :error,
                progress: round(index / total * 100),
                message: "PTIF生成失敗: #{inspect(reason)}"
              })
          end

          {image.id, result}
        end,
        max_concurrency: max_workers,
        timeout: 300_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    succeeded = Enum.count(results, fn {_id, res} -> match?({:ok, _}, res) end)
    failed = total - succeeded

    broadcast_progress(pipeline_id, %{
      event: :pipeline_complete,
      phase: :ptif_generation,
      total: total,
      succeeded: succeeded,
      failed: failed
    })

    {:ok, %{total: total, succeeded: succeeded, failed: failed, results: results}}
  end

  @doc """
  単一画像のクロップ → PTIF → Manifest 生成を実行します。
  FinalizeのLiveViewから呼ばれます。

  ## 引数
    - extracted_image: ExtractedImage レコード
    - pipeline_id: パイプライン識別子

  ## 戻り値
    - {:ok, %{image: ExtractedImage.t(), identifier: String.t()}}
    - {:error, reason}
  """
  def run_single_finalize(extracted_image, pipeline_id) do
    broadcast_progress(pipeline_id, %{
      event: :pipeline_started,
      phase: :finalize,
      message: "ファイナライズを開始します...",
      total: 3
    })

    # ステップ1: PTIF生成
    broadcast_progress(pipeline_id, %{
      event: :task_progress,
      task_id: "finalize-ptif",
      status: :processing,
      progress: 0,
      message: "PTIF生成中..."
    })

    case generate_single_ptif(extracted_image) do
      {:ok, updated_image} ->
        broadcast_progress(pipeline_id, %{
          event: :task_progress,
          task_id: "finalize-ptif",
          status: :completed,
          progress: 33,
          message: "PTIF生成完了"
        })

        # ステップ2: Manifest生成
        broadcast_progress(pipeline_id, %{
          event: :task_progress,
          task_id: "finalize-manifest",
          status: :processing,
          progress: 33,
          message: "IIIF Manifest生成中..."
        })

        identifier = "img-#{extracted_image.id}-#{:rand.uniform(99999)}"

        case create_manifest(extracted_image, identifier) do
          {:ok, _manifest} ->
            broadcast_progress(pipeline_id, %{
              event: :task_progress,
              task_id: "finalize-manifest",
              status: :completed,
              progress: 100,
              message: "IIIF Manifest生成完了"
            })

            broadcast_progress(pipeline_id, %{
              event: :pipeline_complete,
              phase: :finalize,
              total: 2,
              succeeded: 2,
              failed: 0
            })

            {:ok, %{image: updated_image, identifier: identifier}}

          {:error, reason} ->
            broadcast_progress(pipeline_id, %{
              event: :task_progress,
              task_id: "finalize-manifest",
              status: :error,
              progress: 66,
              message: "Manifest生成失敗"
            })

            {:error, reason}
        end

      {:error, reason} ->
        broadcast_progress(pipeline_id, %{
          event: :task_progress,
          task_id: "finalize-ptif",
          status: :error,
          progress: 0,
          message: "PTIF生成に失敗しました"
        })

        {:error, reason}
    end
  end

  @doc "ユニークなパイプラインIDを生成します。"
  def generate_pipeline_id do
    "pl-#{System.system_time(:millisecond)}-#{:rand.uniform(99999)}"
  end

  # --- プライベート関数 ---

  @doc """
  単一画像のPTIF生成（クロップ処理込み）。
  Label 提出時のバックグラウンド呼び出しにも使用されます。

  セキュリティ注記: ptif_dir / cropped_path は内部生成パス（priv/static/iiif_images）で安全。
  """
  def generate_single_ptif(extracted_image) do
    ptif_dir = Path.join(["priv", "static", "iiif_images"])
    File.mkdir_p!(ptif_dir)

    identifier = "img-#{extracted_image.id}-#{:rand.uniform(99999)}"
    ptif_path = Path.join(ptif_dir, "#{identifier}.tif")

    result =
      if extracted_image.geometry do
        # ポリゴンの場合 crop_image が .png で出力する（透明度保持）ため、
        # クロップ出力パスも .png を使用
        cropped_path = Path.join(ptif_dir, "#{identifier}_cropped.png")

        with :ok <-
               ImageProcessor.crop_image(
                 extracted_image.image_path,
                 extracted_image.geometry,
                 cropped_path
               ) do
          # crop_image がポリゴンの場合、拡張子を .png に変更して保存する
          # 実際に出力されたファイルパスを確認
          actual_cropped =
            if File.exists?(cropped_path) do
              cropped_path
            else
              # crop_polygon が .png 拡張子で出力した場合（元が .png なら同じパス）
              Path.rootname(cropped_path) <> ".png"
            end

          case ImageProcessor.generate_ptif(actual_cropped, ptif_path) do
            :ok ->
              File.rm(actual_cropped)
              :ok

            error ->
              File.rm(actual_cropped)
              error
          end
        end
      else
        ImageProcessor.generate_ptif(extracted_image.image_path, ptif_path)
      end

    case result do
      :ok ->
        Ingestion.update_extracted_image(extracted_image, %{ptif_path: ptif_path})

      error ->
        error
    end
  end

  # IIIF Manifest レコードの作成
  defp create_manifest(extracted_image, identifier) do
    %Manifest{}
    |> Manifest.changeset(%{
      extracted_image_id: extracted_image.id,
      identifier: identifier,
      metadata: %{
        "label" => %{
          "en" => [extracted_image.label || identifier],
          "ja" => [extracted_image.label || identifier]
        },
        "summary" => %{
          "en" => [extracted_image.caption || ""],
          "ja" => [extracted_image.caption || ""]
        }
      }
    })
    |> Repo.insert()
  end

  # PubSub で進捗をブロードキャスト
  defp broadcast_progress(pipeline_id, payload) do
    PubSub.broadcast(@pubsub, topic(pipeline_id), {:pipeline_progress, payload})
  end

  # opts に owner_id が含まれている場合は attrs に追加
  defp maybe_put_owner_id(attrs, %{owner_id: owner_id}) when not is_nil(owner_id) do
    Map.put(attrs, :owner_id, owner_id)
  end

  defp maybe_put_owner_id(attrs, _opts), do: attrs

  defp fetch_pdf_source(id), do: Repo.get(PdfSource, id)

  defp update_pdf_source_if_present(id, attrs) do
    case fetch_pdf_source(id) do
      nil -> {:error, :not_found}
      pdf_source -> Ingestion.update_pdf_source(pdf_source, attrs)
    end
  end
end
