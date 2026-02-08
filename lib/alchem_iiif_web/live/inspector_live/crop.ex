defmodule AlchemIiifWeb.InspectorLive.Crop do
  @moduledoc """
  ウィザード Step 3: マニュアルクロップ画面。
  Cropper.js を使用して図版の範囲を定義し、
  Nudge コントロールで微調整を行います。
  キャプションとラベルの手動入力も行います。
  """
  use AlchemIiifWeb, :live_view

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
     |> assign(:crop_data, nil)
     |> assign(:caption, "")
     |> assign(:label, "")}
  end

  @impl true
  def handle_event("update_crop_data", crop_data, socket) do
    {:noreply, assign(socket, :crop_data, crop_data)}
  end

  @impl true
  def handle_event("nudge", %{"direction" => direction}, socket) do
    {:noreply, push_event(socket, "nudge_crop", %{direction: direction, amount: @nudge_amount})}
  end

  @impl true
  def handle_event("update_caption", %{"caption" => caption}, socket) do
    {:noreply, assign(socket, :caption, caption)}
  end

  @impl true
  def handle_event("update_label", %{"label" => label}, socket) do
    {:noreply, assign(socket, :label, label)}
  end

  @impl true
  def handle_event("finalize_crop", _params, socket) do
    crop_data = socket.assigns.crop_data

    if is_nil(crop_data) do
      {:noreply, put_flash(socket, :error, "クロップ範囲を指定してください")}
    else
      # 抽出画像を更新
      {:ok, updated_image} =
        Ingestion.update_extracted_image(socket.assigns.extracted_image, %{
          geometry: crop_data,
          caption: socket.assigns.caption,
          label: socket.assigns.label
        })

      {:noreply, push_navigate(socket, to: ~p"/inspector/finalize/#{updated_image.id}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={3} />

      <div class="crop-area">
        <h2 class="section-title">図版の範囲を指定してください</h2>
        <p class="section-description">
          画像上でドラッグして図版の範囲を選択します。<br /> 方向ボタンで微調整できます。
        </p>

        <%!-- Cropper.js 統合エリア --%>
        <div id="cropper-container" phx-hook="ImageInspectorHook" class="cropper-container">
          <img
            id="inspect-target"
            src={@image_url}
            alt="クロップ対象の画像"
            class="crop-image"
          />
        </div>

        <%!-- Nudge コントロール (アクセシビリティ対応: 最小60x60px) --%>
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
            <div class="nudge-spacer"></div>
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

        <%!-- メタデータ入力フォーム --%>
        <div class="metadata-form">
          <h3 class="form-title">図版の情報を入力してください</h3>

          <div class="form-group">
            <label for="caption-input" class="form-label">キャプション（図の説明）</label>
            <input
              type="text"
              id="caption-input"
              class="form-input"
              value={@caption}
              phx-blur="update_caption"
              phx-value-caption={@caption}
              placeholder="例: 第3図 土器出土状況"
              name="caption"
            />
          </div>

          <div class="form-group">
            <label for="label-input" class="form-label">ラベル（短い識別名）</label>
            <input
              type="text"
              id="label-input"
              class="form-input"
              value={@label}
              phx-blur="update_label"
              phx-value-label={@label}
              placeholder="例: fig-003"
              name="label"
            />
          </div>
        </div>

        <div class="action-bar">
          <.link
            navigate={~p"/inspector/browse/#{@extracted_image.pdf_source_id}"}
            class="btn-secondary btn-large"
          >
            ← 戻る
          </.link>

          <button
            type="button"
            class="btn-primary btn-large"
            phx-click="finalize_crop"
          >
            次へ: 保存 →
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
