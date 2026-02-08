defmodule AlchemIiifWeb.InspectorLive.Upload do
  @moduledoc """
  ウィザード Step 1: PDF アップロード画面。
  PDFファイルをアップロードし、自動的にPNG画像に変換します。
  """
  use AlchemIiifWeb, :live_view

  alias AlchemIiif.Ingestion
  alias AlchemIiif.Ingestion.PdfProcessor

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "PDF をアップロード")
     |> assign(:current_step, 1)
     |> assign(:uploading, false)
     |> assign(:error_message, nil)
     |> allow_upload(:pdf, accept: ~w(.pdf), max_entries: 1, max_file_size: 100_000_000)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("upload_pdf", _params, socket) do
    socket = assign(socket, :uploading, true)

    uploaded_files =
      consume_uploaded_entries(socket, :pdf, fn %{path: path}, entry ->
        # アップロードディレクトリの作成
        upload_dir = Path.join(["priv", "static", "uploads", "pdfs"])
        File.mkdir_p!(upload_dir)

        dest = Path.join(upload_dir, entry.client_name)
        File.cp!(path, dest)
        {:ok, dest}
      end)

    case uploaded_files do
      [pdf_path] ->
        # PDFソースレコードを作成
        {:ok, pdf_source} =
          Ingestion.create_pdf_source(%{
            filename: Path.basename(pdf_path),
            status: "converting"
          })

        # PNG変換を実行 (バックグラウンドで)
        output_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])

        case PdfProcessor.convert_to_images(pdf_path, output_dir) do
          {:ok, %{page_count: page_count}} ->
            {:ok, _updated} =
              Ingestion.update_pdf_source(pdf_source, %{
                page_count: page_count,
                status: "ready"
              })

            {:noreply,
             socket
             |> assign(:uploading, false)
             |> put_flash(:info, "PDF を正常にアップロードしました！（#{page_count}ページ）")
             |> push_navigate(to: ~p"/inspector/browse/#{pdf_source.id}")}

          {:error, reason} ->
            Ingestion.update_pdf_source(pdf_source, %{status: "error"})

            {:noreply,
             socket
             |> assign(:uploading, false)
             |> assign(:error_message, reason)}
        end

      _ ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:error_message, "PDFファイルを選択してください")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={1} />

      <div class="upload-area">
        <h2 class="section-title">PDFファイルをアップロード</h2>
        <p class="section-description">考古学報告書のPDFファイルを選択してください。</p>

        <form id="upload-form" phx-submit="upload_pdf" phx-change="validate">
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
        </form>
      </div>
    </div>
    """
  end

  # ウィザードヘッダーコンポーネント
  defp wizard_header(assigns) do
    ~H"""
    <nav class="wizard-header" aria-label="進捗ステップ">
      <ol class="wizard-steps">
        <li class={"wizard-step #{if @current_step >= 1, do: "active", else: ""}"}>
          <span class="step-number">1</span>
          <span class="step-label">アップロード</span>
        </li>
        <li class={"wizard-step #{if @current_step >= 2, do: "active", else: ""}"}>
          <span class="step-number">2</span>
          <span class="step-label">ページ選択</span>
        </li>
        <li class={"wizard-step #{if @current_step >= 3, do: "active", else: ""}"}>
          <span class="step-number">3</span>
          <span class="step-label">クロップ</span>
        </li>
        <li class={"wizard-step #{if @current_step >= 4, do: "active", else: ""}"}>
          <span class="step-number">4</span>
          <span class="step-label">保存</span>
        </li>
      </ol>
    </nav>
    """
  end
end
