defmodule AlchemIiifWeb.InspectorLive.Upload do
  @moduledoc """
  ウィザード Step 1: PDF アップロード画面 + 要修正タブ。
  PDFファイルをアップロードし、並列パイプラインで自動的にPNG画像に変換します。
  差し戻された画像の一覧も表示し、修正・再提出ワークフローを提供します。
  """
  use AlchemIiifWeb, :live_view

  import AlchemIiifWeb.WizardComponents

  alias AlchemIiif.Ingestion
  alias AlchemIiif.Pipeline
  alias AlchemIiif.UploadStore

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    # WebSocket 接続時のみユーザー単位の完了通知を購読
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        AlchemIiif.PubSub,
        Pipeline.pdf_pipeline_topic(current_user.id)
      )
    end

    rejected_images = Ingestion.list_rejected_images(current_user)

    {:ok,
     socket
     |> assign(:page_title, "PDF をアップロード")
     |> assign(:current_step, 1)
     |> assign(:uploading, false)
     |> assign(:error_message, nil)
     |> assign(:active_tab, :upload)
     |> assign(:rejected_images, rejected_images)
     |> assign(:rejected_count, length(rejected_images))
     |> assign(:current_page, 0)
     |> assign(:total_pages, 0)
     |> assign(:color_mode, "mono")
     |> assign(:max_pages, max_pdf_pages())
     |> assign(:report_title, "")
     |> assign(:investigating_org, "")
     |> assign(:survey_year, nil)
     |> assign(:site_code, "")
     |> assign(:license_uri, "")
     |> allow_upload(:pdf,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: max_pdf_upload_bytes()
     )}
  end

  @impl true
  def handle_event("validate", params, socket) do
    color_mode = get_in(params, ["color_mode"]) || socket.assigns.color_mode
    max_pages = parse_max_pages(get_in(params, ["max_pages"]), socket.assigns.max_pages)

    {:noreply,
     socket
     |> assign(:color_mode, color_mode)
     |> assign(:max_pages, max_pages)
     |> assign(:report_title, get_in(params, ["report_title"]) || socket.assigns.report_title)
     |> assign(
       :investigating_org,
       get_in(params, ["investigating_org"]) || socket.assigns.investigating_org
     )
     |> assign(
       :survey_year,
       parse_survey_year(get_in(params, ["survey_year"])) || socket.assigns.survey_year
     )
     |> assign(:site_code, get_in(params, ["site_code"]) || socket.assigns.site_code)
     |> assign(:license_uri, get_in(params, ["license_uri"]) || socket.assigns.license_uri)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    case tab do
      "upload" -> {:noreply, assign(socket, :active_tab, :upload)}
      "rejected" -> {:noreply, assign(socket, :active_tab, :rejected)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  # セキュリティ注記: upload_dir は固定パス（priv/uploads/pdfs）、
  # path は Phoenix LiveView の一時ファイル、dest は内部生成で安全。
  def handle_event("upload_pdf", params, socket) do
    color_mode = get_in(params, ["color_mode"]) || socket.assigns.color_mode
    max_pages_param = get_in(params, ["max_pages"])
    max_pages = parse_max_pages(max_pages_param, socket.assigns.max_pages)

    processing_opts = processing_options(color_mode, max_pages, max_pages_param)
    socket = assign(socket, uploading: true, color_mode: color_mode, max_pages: max_pages)

    uploaded_files =
      consume_uploaded_entries(socket, :pdf, fn %{path: path}, entry ->
        # アップロードディレクトリの作成
        upload_dir = UploadStore.pdfs_dir()
        File.mkdir_p!(upload_dir)

        # ファイル名にタイムスタンプを付与して衝突を防止
        timestamp = System.system_time(:second)
        ext = Path.extname(entry.client_name)
        base = Path.basename(entry.client_name, ext)
        versioned_name = "#{base}-#{timestamp}#{ext}"
        dest = Path.join(upload_dir, versioned_name)
        File.cp!(path, dest)
        {:ok, dest}
      end)

    case uploaded_files do
      [pdf_path] ->
        # PDFソースレコードを作成
        case Ingestion.create_pdf_source(%{
               filename: Path.basename(pdf_path),
               status: "converting",
               user_id: socket.assigns.current_user.id,
               report_title: non_empty_or_nil(socket.assigns.report_title),
               investigating_org: non_empty_or_nil(socket.assigns.investigating_org),
               survey_year: socket.assigns.survey_year,
               site_code: non_empty_or_nil(socket.assigns.site_code),
               license_uri: non_empty_or_nil(socket.assigns.license_uri)
             }) do
          {:ok, pdf_source} ->
            # パイプラインIDを生成
            pipeline_id = Pipeline.generate_pipeline_id()

            owner_id = socket.assigns.current_user.id

            # ユーザーに紐付くWorkerに処理を委譲（カラーモードを渡す）
            AlchemIiif.PdfProcessingDispatcher.dispatch_pdf_processing(
              owner_id,
              pdf_source,
              pdf_path,
              pipeline_id,
              processing_opts
            )

            # 完了メッセージを購読する
            Phoenix.PubSub.subscribe(AlchemIiif.PubSub, "pdf_source_#{pdf_source.id}")

            # 処理中のUI状態を維持
            {:noreply,
             socket
             |> assign(:uploading, true)
             |> assign(:processing_pdf_id, pdf_source.id)
             |> put_flash(:info, "裏側でPDF処理を開始しました。完了するまでこの画面でお待ちください...")}

          {:error, changeset} ->
            errors =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
              |> Enum.map_join("、", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

            {:noreply,
             socket
             |> assign(:uploading, false)
             |> put_flash(:error, "入力エラー: #{errors}")}
        end

      _ ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:error_message, "PDFファイルを選択してください")}
    end
  end

  @impl true
  def handle_info({:extraction_progress, current, total}, socket) do
    {:noreply, assign(socket, current_page: current, total_pages: total)}
  end

  @impl true
  def handle_info({:extraction_complete, document_id}, socket) do
    {:noreply,
     socket
     |> assign(:uploading, false)
     |> assign(:current_page, 0)
     |> assign(:total_pages, 0)
     |> put_flash(:info, "PDFの処理が完了しました！")
     |> push_navigate(to: ~p"/lab/browse/#{document_id}")}
  end

  @impl true
  def handle_info({:pdf_processed, pdf_source_id}, socket) do
    if socket.assigns[:processing_pdf_id] == pdf_source_id do
      {:noreply,
       socket
       |> assign(:uploading, false)
       |> put_flash(:info, "PDFの処理が完了しました！")
       |> push_navigate(to: ~p"/lab/browse/#{pdf_source_id}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={@current_step} />

      <%!-- タブナビゲーション --%>
      <div class="lab-tabs">
        <button
          type="button"
          class={"lab-tab #{if @active_tab == :upload, do: "lab-tab-active", else: ""}"}
          phx-click="switch_tab"
          phx-value-tab="upload"
        >
          📤 アップロード
        </button>
        <button
          type="button"
          class={"lab-tab #{if @active_tab == :rejected, do: "lab-tab-active", else: ""} #{if @rejected_count > 0, do: "lab-tab-alert", else: ""}"}
          phx-click="switch_tab"
          phx-value-tab="rejected"
        >
          ⚠️ 要修正
          <%= if @rejected_count > 0 do %>
            <span class="tab-badge">{@rejected_count}</span>
          <% end %>
        </button>
      </div>

      <%!-- アップロードタブ --%>
      <%= if @active_tab == :upload do %>
        <div class="upload-area">
          <h2 class="section-title">PDFファイルをアップロード</h2>
          <p class="section-description">考古学報告書のPDFファイルを選択してください。</p>

          <form id="upload-form" phx-submit="upload_pdf" phx-change="validate">
            <%!-- カラーモード切替ラジオボタン --%>
            <div class="color-mode-selector">
              <span class="color-mode-label">変換モード:</span>
              <label class={"color-mode-option #{if @color_mode == "mono", do: "selected", else: ""}"}>
                <input
                  type="radio"
                  name="color_mode"
                  value="mono"
                  checked={@color_mode == "mono"}
                /> 🖤 モノクロモード（高速）
              </label>
              <label class={"color-mode-option #{if @color_mode == "color", do: "selected", else: ""}"}>
                <input
                  type="radio"
                  name="color_mode"
                  value="color"
                  checked={@color_mode == "color"}
                /> 🎨 カラーモード（標準）
              </label>
            </div>

            <div class="color-mode-selector">
              <label for="pdf-page-limit-input" class="color-mode-label">
                読み込みページ数の目安:
              </label>
              <input
                type="number"
                id="pdf-page-limit-input"
                name="max_pages"
                value={@max_pages}
                min="1"
                max={max_pdf_pages()}
                step="1"
                inputmode="numeric"
                class="input input-bordered input-sm w-28"
                aria-label="PDFを読み込むページ数の目安"
              />
              <span class="text-sm text-base-content/70">
                ページまで（上限 {max_pdf_pages()} ページ）
              </span>
            </div>

            <%!-- 報告書情報セクション --%>
            <details open class="bibliographic-section">
              <summary class="bibliographic-summary">📋 報告書情報（任意）</summary>
              <div class="bibliographic-fields">
                <div class="form-group">
                  <label for="report-title-input" class="form-label">📖 報告書名</label>
                  <input
                    type="text"
                    id="report-title-input"
                    class="form-input form-input-large"
                    value={@report_title}
                    name="report_title"
                    placeholder="例：令和6年度 ○○遺跡発掘調査報告書"
                    aria-label="報告書名"
                  />
                </div>

                <div class="form-group">
                  <label for="investigating-org-input" class="form-label">🏛️ 調査機関名</label>
                  <input
                    type="text"
                    id="investigating-org-input"
                    class="form-input form-input-large"
                    value={@investigating_org}
                    name="investigating_org"
                    placeholder="例：○○市教育委員会"
                    aria-label="調査機関名"
                  />
                </div>

                <div class="form-group">
                  <label for="survey-year-input" class="form-label">📅 調査年度（西暦）</label>
                  <input
                    type="number"
                    id="survey-year-input"
                    class="form-input form-input-large"
                    value={@survey_year}
                    name="survey_year"
                    min="1900"
                    max={Date.utc_today().year}
                    aria-label="調査年度"
                  />
                </div>

                <div class="form-group">
                  <label for="site-code-input" class="form-label">🗺️ 遺跡コード</label>
                  <input
                    type="text"
                    id="site-code-input"
                    class="form-input form-input-large"
                    value={@site_code}
                    name="site_code"
                    placeholder="例：15-201-001"
                    aria-label="遺跡コード"
                  />
                  <p class="form-help-text">
                    全国遺跡地図のコード（都道府県2桁-市区町村3〜4桁-連番3〜4桁）
                  </p>
                </div>

                <div class="form-group">
                  <label for="license-uri-input" class="form-label">⚖️ ライセンスURI</label>
                  <input
                    type="text"
                    id="license-uri-input"
                    class="form-input form-input-large"
                    value={@license_uri}
                    name="license_uri"
                    placeholder="https://creativecommons.org/licenses/by/4.0/"
                    aria-label="ライセンスURI"
                  />
                  <p class="form-help-text">
                    未入力の場合は「転載不可（InC-1.0）」が自動設定されます。
                    CC BY 4.0 の場合は https://creativecommons.org/licenses/by/4.0/ を入力してください。
                  </p>
                </div>
              </div>
            </details>

            <div class="upload-dropzone" phx-drop-target={@uploads.pdf.ref}>
              <.live_file_input upload={@uploads.pdf} class="file-input" />
              <div class="dropzone-content">
                <span class="dropzone-icon">📄</span>
                <span class="dropzone-text">ここにPDFをドラッグ、またはクリックして選択</span>
              </div>
            </div>

            <%= for entry <- @uploads.pdf.entries do %>
              <div class="upload-entry">
                <span class="entry-name">{entry.client_name}</span>
                <progress value={entry.progress} max="100" class="upload-progress">
                  {entry.progress}%
                </progress>
              </div>

              <%!-- エントリ単位のアップロードエラー表示 --%>
              <%= for err <- upload_errors(@uploads.pdf, entry) do %>
                <div class="error-message" role="alert">
                  <span class="error-icon">⚠️</span>
                  {translate_upload_error(err)}
                </div>
              <% end %>
            <% end %>

            <%!-- 全体のアップロードエラー表示 --%>
            <%= for err <- upload_errors(@uploads.pdf) do %>
              <div class="error-message" role="alert">
                <span class="error-icon">⚠️</span>
                {translate_upload_error(err)}
              </div>
            <% end %>

            <%= if @error_message do %>
              <div class="error-message" role="alert">
                <span class="error-icon">⚠️</span>
                {@error_message}
              </div>
            <% end %>

            <button
              type="submit"
              class="btn-primary btn-large"
              disabled={@uploading || @uploads.pdf.entries == []}
            >
              <%= if @uploading do %>
                <span class="spinner"></span> アップロード中...
              <% else %>
                📤 アップロードして変換する
              <% end %>
            </button>

            <%= if @uploading && @total_pages > 0 do %>
              <div class="mt-4">
                <div class="flex justify-between mb-1">
                  <span class="text-sm font-medium text-gray-700">PDFを読み込み中...</span>
                  <span class="text-sm font-medium text-gray-700">
                    {@current_page} / {@total_pages} ページ
                  </span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div
                    class="bg-blue-600 h-2.5 rounded-full transition-all duration-500"
                    style={"width: #{trunc(@current_page / max(@total_pages, 1) * 100)}%"}
                  >
                  </div>
                </div>
              </div>
            <% end %>
          </form>
        </div>
      <% end %>

      <%!-- 要修正タブ --%>
      <%= if @active_tab == :rejected do %>
        <div class="rejected-area">
          <h2 class="section-title">⚠️ 要修正の図版</h2>
          <p class="section-description">
            レビューで差し戻された図版です。修正して再提出してください。
          </p>

          <%= if @rejected_images == [] do %>
            <div class="no-results">
              <span class="no-results-icon">✅</span>
              <p class="section-description">
                差し戻された図版はありません。すべて処理済みです！
              </p>
            </div>
          <% else %>
            <div class="rejected-list">
              <%= for image <- @rejected_images do %>
                <div class="rejected-card" id={"rejected-card-#{image.id}"}>
                  <%!-- Row 1: メタ情報 & アクション --%>
                  <div class="rejected-card-row1">
                    <div class="rejected-card-info">
                      <span class="rejected-card-label">{image.label || "名称未設定"}</span>
                      <%= if image.pdf_source do %>
                        <span class="meta-tag">📄 {image.pdf_source.filename}</span>
                      <% end %>
                      <span class="meta-tag">P.{image.page_number}</span>
                    </div>
                    <.link
                      navigate={~p"/lab/label/#{image.id}"}
                      class="btn-resubmit-sm"
                    >
                      🔧 修正する
                    </.link>
                  </div>
                  <%!-- Row 2: レビューコメント（存在する場合のみ） --%>
                  <%= if image.review_comment && image.review_comment != "" do %>
                    <div class="rejected-card-comment">
                      {image.review_comment}
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # アップロードエラーを日本語に変換するヘルパー
  defp translate_upload_error(:too_large), do: "ファイルサイズが上限を超えています。"
  defp translate_upload_error(:too_many_files), do: "アップロードできるファイルは1つだけです。"
  defp translate_upload_error(:not_accepted), do: "PDFファイルのみアップロード可能です。"
  defp translate_upload_error(err), do: "アップロードエラー: #{inspect(err)}"

  defp max_pdf_upload_bytes do
    Application.get_env(:alchem_iiif, :max_pdf_upload_bytes, 100_000_000)
  end

  defp max_pdf_pages do
    Application.get_env(:alchem_iiif, :pdf_max_pages, 200)
    |> max(1)
  end

  defp parse_max_pages(nil, current), do: current || max_pdf_pages()
  defp parse_max_pages("", current), do: current || max_pdf_pages()

  defp parse_max_pages(value, _current) when is_integer(value) do
    clamp_max_pages(value)
  end

  defp parse_max_pages(value, current) when is_binary(value) do
    case Integer.parse(value) do
      {pages, ""} -> clamp_max_pages(pages)
      _ -> current || max_pdf_pages()
    end
  end

  defp parse_max_pages(_value, current), do: current || max_pdf_pages()

  defp clamp_max_pages(pages) do
    pages
    |> max(1)
    |> min(max_pdf_pages())
  end

  defp processing_options(color_mode, _max_pages, nil), do: color_mode

  defp processing_options(color_mode, max_pages, _max_pages_param) do
    %{color_mode: color_mode, max_pages: max_pages}
  end

  # 空文字列を nil に変換するヘルパー
  defp non_empty_or_nil(""), do: nil
  defp non_empty_or_nil(value), do: value

  # 調査年度文字列を整数に変換するヘルパー
  defp parse_survey_year(nil), do: nil
  defp parse_survey_year(""), do: nil

  defp parse_survey_year(value) when is_binary(value) do
    case Integer.parse(value) do
      {year, ""} -> year
      _ -> nil
    end
  end

  defp parse_survey_year(value), do: value
end
