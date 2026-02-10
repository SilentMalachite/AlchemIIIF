defmodule AlchemIiifWeb.InspectorLive.Crop do
  @moduledoc """
  ウィザード Step 3: クロップ専用画面。
  Cropper.js を使用して図版の範囲を定義し、
  Nudge コントロール（上下左右 + 拡大/縮小）で微調整を行います。
  Undo 機能と Auto-Save を搭載。
  """
  use AlchemIiifWeb, :live_view

  import AlchemIiifWeb.WizardComponents

  alias AlchemIiif.Ingestion

  @nudge_amount 5

  @impl true
  def mount(%{"image_id" => image_id}, _session, socket) do
    extracted_image = Ingestion.get_extracted_image!(image_id)

    # 画像のURLを生成（priv/static からの相対パス）
    image_url =
      extracted_image.image_path
      |> String.replace_leading("priv/static/", "/")

    {:ok,
     socket
     |> assign(:page_title, "図版をクロップ")
     |> assign(:current_step, 3)
     |> assign(:extracted_image, extracted_image)
     |> assign(:image_url, image_url)
     |> assign(:crop_data, extracted_image.geometry)
     |> assign(:undo_stack, [])
     |> assign(:save_state, :idle)}
  end

  @impl true
  def handle_event("update_crop_data", crop_data, socket) do
    # 現在の値を Undo スタックに保存
    undo_stack =
      case socket.assigns.crop_data do
        nil -> socket.assigns.undo_stack
        current -> [current | socket.assigns.undo_stack] |> Enum.take(20)
      end

    {:noreply,
     socket
     |> assign(:crop_data, crop_data)
     |> assign(:undo_stack, undo_stack)
     |> auto_save_crop(crop_data)}
  end

  @impl true
  def handle_event("nudge", %{"direction" => direction}, socket) do
    # 現在の値を Undo スタックに保存
    undo_stack =
      case socket.assigns.crop_data do
        nil -> socket.assigns.undo_stack
        current -> [current | socket.assigns.undo_stack] |> Enum.take(20)
      end

    {:noreply,
     socket
     |> assign(:undo_stack, undo_stack)
     |> push_event("nudge_crop", %{direction: direction, amount: @nudge_amount})}
  end

  @impl true
  def handle_event("undo", _params, socket) do
    case socket.assigns.undo_stack do
      [previous | rest] ->
        {:noreply,
         socket
         |> assign(:crop_data, previous)
         |> assign(:undo_stack, rest)
         |> push_event("restore_crop", %{crop_data: previous})
         |> auto_save_crop(previous)}

      [] ->
        {:noreply, put_flash(socket, :info, "元に戻す操作はありません")}
    end
  end

  @impl true
  def handle_event("proceed_to_label", _params, socket) do
    crop_data = socket.assigns.crop_data

    if is_nil(crop_data) do
      {:noreply, put_flash(socket, :error, "クロップ範囲を指定してください")}
    else
      # クロップデータを保存してラベリング画面に遷移
      {:ok, _updated_image} =
        Ingestion.update_extracted_image(socket.assigns.extracted_image, %{
          geometry: crop_data
        })

      {:noreply, push_navigate(socket, to: ~p"/lab/label/#{socket.assigns.extracted_image.id}")}
    end
  end

  @impl true
  def handle_info(:auto_save_complete, socket) do
    {:noreply, assign(socket, :save_state, :saved)}
  end

  # Auto-Save ヘルパー — draft ステータスのまま DB に保存
  defp auto_save_crop(socket, crop_data) do
    socket = assign(socket, :save_state, :saving)

    # 非同期で保存（UIをブロックしない）
    lv_pid = self()

    Task.start(fn ->
      Ingestion.update_extracted_image(socket.assigns.extracted_image, %{
        geometry: crop_data
      })

      send(lv_pid, :auto_save_complete)
    end)

    socket
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={@current_step} />

      <div class="crop-area">
        <h2 class="section-title">✂️ 図版の範囲を指定してください</h2>
        <p class="section-description">
          画像上でドラッグして図版の範囲を選択します。<br /> 方向ボタンで微調整できます。
        </p>

        <%!-- Auto-Save ステータス --%>
        <.auto_save_indicator state={@save_state} />

        <%!-- Cropper.js 統合エリア --%>
        <div id="cropper-container" phx-hook="ImageInspectorHook" class="cropper-container">
          <img
            id="inspect-target"
            src={@image_url}
            alt="クロップ対象の画像"
            class="crop-image"
          />
        </div>

        <%!-- Nudge コントロール (D-pad: 上下左右 + 拡大/縮小) --%>
        <div class="nudge-controls" role="group" aria-label="クロップ範囲の微調整">
          <div class="nudge-row">
            <button
              type="button"
              class="nudge-btn"
              phx-click="nudge"
              phx-value-direction="up"
              aria-label="上に移動"
            >
              ↑
            </button>
          </div>
          <div class="nudge-row">
            <button
              type="button"
              class="nudge-btn"
              phx-click="nudge"
              phx-value-direction="left"
              aria-label="左に移動"
            >
              ←
            </button>
            <button
              type="button"
              class="nudge-btn nudge-shrink"
              phx-click="nudge"
              phx-value-direction="shrink"
              aria-label="縮小"
            >
              −
            </button>
            <button
              type="button"
              class="nudge-btn nudge-expand"
              phx-click="nudge"
              phx-value-direction="expand"
              aria-label="拡大"
            >
              ＋
            </button>
            <button
              type="button"
              class="nudge-btn"
              phx-click="nudge"
              phx-value-direction="right"
              aria-label="右に移動"
            >
              →
            </button>
          </div>
          <div class="nudge-row">
            <button
              type="button"
              class="nudge-btn"
              phx-click="nudge"
              phx-value-direction="down"
              aria-label="下に移動"
            >
              ↓
            </button>
          </div>
        </div>

        <%!-- Undo ボタン --%>
        <div class="undo-bar">
          <button
            type="button"
            class="btn-undo"
            phx-click="undo"
            disabled={@undo_stack == []}
            aria-label="元に戻す"
          >
            ↩️ 元に戻す
            <%= if @undo_stack != [] do %>
              <span class="undo-count">({length(@undo_stack)})</span>
            <% end %>
          </button>
        </div>

        <div class="action-bar">
          <.link
            navigate={~p"/lab/browse/#{@extracted_image.pdf_source_id}"}
            class="btn-secondary btn-large"
          >
            ← 戻る
          </.link>

          <button
            type="button"
            class="btn-primary btn-large"
            phx-click="proceed_to_label"
          >
            次へ: ラベリング →
          </button>
        </div>
      </div>
    </div>
    """
  end
end
