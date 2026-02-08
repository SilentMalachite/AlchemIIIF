defmodule AlchemIiifWeb.InspectorLive.Browse do
  @moduledoc """
  ウィザード Step 2: ページ閲覧・選択画面。
  PDFから変換されたページのサムネイルをグリッド表示し、
  ユーザーが図版を含むページを手動で選択します。
  """
  use AlchemIiifWeb, :live_view

  alias AlchemIiif.Ingestion

  @impl true
  def mount(%{"pdf_source_id" => pdf_source_id}, _session, socket) do
    pdf_source = Ingestion.get_pdf_source!(pdf_source_id)
    pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])

    # ページ画像のリストを取得
    page_images =
      if File.dir?(pages_dir) do
        pages_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".png"))
        |> Enum.sort()
        |> Enum.with_index(1)
        |> Enum.map(fn {filename, index} ->
          %{
            filename: filename,
            page_number: index,
            # 静的ファイルとして配信するパス
            url: "/uploads/pages/#{pdf_source.id}/#{filename}"
          }
        end)
      else
        []
      end

    {:ok,
     socket
     |> assign(:page_title, "ページを選択")
     |> assign(:current_step, 2)
     |> assign(:pdf_source, pdf_source)
     |> assign(:page_images, page_images)
     |> assign(:selected_page, nil)}
  end

  @impl true
  def handle_event("select_page", %{"page" => page_number}, socket) do
    page_number = String.to_integer(page_number)
    {:noreply, assign(socket, :selected_page, page_number)}
  end

  @impl true
  def handle_event("proceed_to_crop", _params, socket) do
    case socket.assigns.selected_page do
      nil ->
        {:noreply, put_flash(socket, :error, "ページを選択してください")}

      page_number ->
        pdf_source = socket.assigns.pdf_source

        # 選択されたページの画像パスを取得
        page_image =
          Enum.find(socket.assigns.page_images, &(&1.page_number == page_number))

        # ExtractedImageレコードを作成
        image_path =
          Path.join([
            "priv",
            "static",
            "uploads",
            "pages",
            "#{pdf_source.id}",
            page_image.filename
          ])

        {:ok, extracted_image} =
          Ingestion.create_extracted_image(%{
            pdf_source_id: pdf_source.id,
            page_number: page_number,
            image_path: image_path
          })

        {:noreply, push_navigate(socket, to: ~p"/inspector/crop/#{extracted_image.id}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={2} />

      <div class="browse-area">
        <h2 class="section-title">ページを選択してください</h2>
        <p class="section-description">
          「{@pdf_source.filename}」のページ一覧です。<br /> 図版や挿絵が含まれているページをクリックして選択してください。
        </p>

        <div class="page-grid">
          <%= for page <- @page_images do %>
            <button
              type="button"
              class={"page-thumbnail #{if @selected_page == page.page_number, do: "selected", else: ""}"}
              phx-click="select_page"
              phx-value-page={page.page_number}
              aria-label={"ページ #{page.page_number}"}
              aria-pressed={@selected_page == page.page_number}
            >
              <img
                src={page.url}
                alt={"ページ #{page.page_number}"}
                loading="lazy"
              />
              <span class="page-label">ページ {page.page_number}</span>
            </button>
          <% end %>
        </div>

        <div class="action-bar">
          <.link navigate={~p"/inspector"} class="btn-secondary btn-large">
            ← 戻る
          </.link>

          <button
            type="button"
            class="btn-primary btn-large"
            phx-click="proceed_to_crop"
            disabled={@selected_page == nil}
          >
            次へ: クロップ →
          </button>
        </div>
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
