defmodule AlchemIiifWeb.InspectorLive.Crop do
  @moduledoc """
  ウィザード Step 3: クロップ専用画面。
  カスタム ImageSelection Hook を使用して図版の範囲を定義し、
  Nudge コントロール（上下左右 + 拡大/縮小）で微調整を行います。
  SVG オーバーレイで選択範囲を可視化。
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

    # 既存の geometry、または空のデフォルト値
    crop_rect =
      case extracted_image.geometry do
        %{"x" => _, "y" => _, "width" => _, "height" => _} = geo -> geo
        _ -> nil
      end

    {:ok,
     socket
     |> assign(:page_title, "図版をクロップ")
     |> assign(:current_step, 3)
     |> assign(:extracted_image, extracted_image)
     |> assign(:image_url, image_url)
     |> assign(:crop_rect, crop_rect)
     |> assign(:undo_stack, [])
     |> assign(:save_state, :idle)
     |> assign(:save_timer, nil)}
  end

  # JS Hook からのドラッグ選択イベント
  @impl true
  def handle_event("update_crop", params, socket) do
    crop_rect = %{
      "x" => to_int(params["x"]),
      "y" => to_int(params["y"]),
      "width" => to_int(params["width"]),
      "height" => to_int(params["height"])
    }

    # 現在の値を Undo スタックに保存
    undo_stack = push_undo(socket.assigns.crop_rect, socket.assigns.undo_stack)

    {:noreply,
     socket
     |> assign(:crop_rect, crop_rect)
     |> assign(:undo_stack, undo_stack)
     |> auto_save_crop(crop_rect)}
  end

  # 旧イベント名の後方互換性（update_crop_data）
  @impl true
  def handle_event("update_crop_data", crop_rect, socket) do
    undo_stack = push_undo(socket.assigns.crop_rect, socket.assigns.undo_stack)

    {:noreply,
     socket
     |> assign(:crop_rect, crop_rect)
     |> assign(:undo_stack, undo_stack)
     |> auto_save_crop(crop_rect)}
  end

  @impl true
  def handle_event("nudge", %{"direction" => direction} = params, socket) do
    amount = to_int(params["amount"] || @nudge_amount)

    # 現在の値を Undo スタックに保存
    undo_stack = push_undo(socket.assigns.crop_rect, socket.assigns.undo_stack)

    {:noreply,
     socket
     |> assign(:undo_stack, undo_stack)
     |> push_event("nudge_crop", %{direction: direction, amount: amount})}
  end

  @impl true
  def handle_event("undo", _params, socket) do
    case socket.assigns.undo_stack do
      [previous | rest] ->
        {:noreply,
         socket
         |> assign(:crop_rect, previous)
         |> assign(:undo_stack, rest)
         |> push_event("restore_crop", %{crop_data: previous})
         |> auto_save_crop(previous)}

      [] ->
        {:noreply, put_flash(socket, :info, "元に戻す操作はありません")}
    end
  end

  @impl true
  def handle_event("proceed_to_label", _params, socket) do
    crop_rect = socket.assigns.crop_rect

    if is_nil(crop_rect) do
      {:noreply, put_flash(socket, :error, "クロップ範囲を指定してください")}
    else
      # クロップデータを保存してラベリング画面に遷移
      {:ok, _updated_image} =
        Ingestion.update_extracted_image(socket.assigns.extracted_image, %{
          geometry: crop_rect
        })

      {:noreply, push_navigate(socket, to: ~p"/lab/label/#{socket.assigns.extracted_image.id}")}
    end
  end

  @impl true
  def handle_info(:auto_save_complete, socket) do
    {:noreply, assign(socket, :save_state, :saved)}
  end

  # デバウンスタイマー発火 — 最終値のみ DB に保存
  @impl true
  def handle_info(:debounced_save, socket) do
    crop_rect = socket.assigns.crop_rect

    if crop_rect do
      lv_pid = self()

      Task.start(fn ->
        Ingestion.update_extracted_image(socket.assigns.extracted_image, %{
          geometry: crop_rect
        })

        send(lv_pid, :auto_save_complete)
      end)

      {:noreply,
       socket
       |> assign(:save_state, :saving)
       |> assign(:save_timer, nil)}
    else
      {:noreply, assign(socket, :save_timer, nil)}
    end
  end

  # Undo スタックにプッシュ（最大20件）
  defp push_undo(nil, stack), do: stack
  defp push_undo(current, stack), do: [current | stack] |> Enum.take(20)

  # 安全な整数変換
  defp to_int(val) when is_integer(val), do: val
  defp to_int(val) when is_float(val), do: round(val)

  defp to_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  # Auto-Save ヘルパー — デバウンス方式で最終値のみ DB に保存（500ms）
  defp auto_save_crop(socket, _crop_rect) do
    # 前回のタイマーをキャンセル
    if socket.assigns.save_timer do
      Process.cancel_timer(socket.assigns.save_timer)
    end

    # 500ms 後に最終値を保存（連続操作中は前のタイマーがキャンセルされる）
    timer = Process.send_after(self(), :debounced_save, 500)
    assign(socket, :save_timer, timer)
  end

  # crop_rect からSVGオーバーレイ用の値を安全に取得
  defp crop_x(nil), do: 0
  defp crop_x(%{"x" => x}), do: x
  defp crop_x(_), do: 0

  defp crop_y(nil), do: 0
  defp crop_y(%{"y" => y}), do: y
  defp crop_y(_), do: 0

  defp crop_w(nil), do: 0
  defp crop_w(%{"width" => w}), do: w
  defp crop_w(_), do: 0

  defp crop_h(nil), do: 0
  defp crop_h(%{"height" => h}), do: h
  defp crop_h(_), do: 0

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

        <%!-- 画像 + SVG オーバーレイ --%>
        <div id="cropper-container" phx-hook="ImageSelection" class="cropper-container">
          <img
            id="inspect-target"
            src={@image_url}
            alt="クロップ対象の画像"
            class="crop-image"
          />
          <%!-- 初期クロップデータ（JS に渡すための data 属性） --%>
          <span
            class="crop-init-data"
            data-crop-x={crop_x(@crop_rect)}
            data-crop-y={crop_y(@crop_rect)}
            data-crop-w={crop_w(@crop_rect)}
            data-crop-h={crop_h(@crop_rect)}
            style="display:none;"
          />
          <%!-- SVG オーバーレイ（JS Hook が制御するため phx-update="ignore"） --%>
          <div id="crop-svg-container" phx-update="ignore">
            <svg class="crop-overlay" preserveAspectRatio="none">
              <defs>
                <mask id="crop-dim-mask">
                  <rect class="dim-mask" fill="white" x="0" y="0" width="100%" height="100%" />
                  <rect class="dim-cutout" fill="black" x="0" y="0" width="0" height="0" />
                </mask>
              </defs>
              <%!-- 半透明の暗転マスク --%>
              <rect
                class="dim-overlay"
                x="0" y="0" width="100%" height="100%"
                fill="rgba(0,0,0,0.45)"
                mask="url(#crop-dim-mask)"
              />
              <%!-- 選択範囲の枠線（Harvest Gold テーマ） --%>
              <rect
                class="selection-rect"
                x="0" y="0" width="0" height="0"
                fill="#E6B422"
                fill-opacity="0.2"
                stroke="#E6B422"
                stroke-width="2"
                stroke-dasharray="8 4"
                style="display:none;"
              />
            </svg>
          </div>
        </div>

        <%!-- Nudge コントロール (D-pad: 上下左右 + 拡大/縮小) --%>
        <div class="nudge-controls" role="group" aria-label="クロップ範囲の微調整">
          <div class="nudge-row">
            <button
              type="button"
              class="nudge-btn"
              phx-click="nudge"
              phx-value-direction="up"
              phx-value-amount="5"
              aria-label="上に移動"
            >
              <.icon name="hero-arrow-up-solid" class="nudge-icon" />
            </button>
          </div>
          <div class="nudge-row">
            <button
              type="button"
              class="nudge-btn"
              phx-click="nudge"
              phx-value-direction="left"
              phx-value-amount="5"
              aria-label="左に移動"
            >
              <.icon name="hero-arrow-left-solid" class="nudge-icon" />
            </button>
            <button
              type="button"
              class="nudge-btn nudge-shrink"
              phx-click="nudge"
              phx-value-direction="shrink"
              phx-value-amount="5"
              aria-label="縮小"
            >
              <.icon name="hero-arrows-pointing-in-solid" class="nudge-icon" />
            </button>
            <button
              type="button"
              class="nudge-btn nudge-expand"
              phx-click="nudge"
              phx-value-direction="expand"
              phx-value-amount="5"
              aria-label="拡大"
            >
              <.icon name="hero-arrows-pointing-out-solid" class="nudge-icon" />
            </button>
            <button
              type="button"
              class="nudge-btn"
              phx-click="nudge"
              phx-value-direction="right"
              phx-value-amount="5"
              aria-label="右に移動"
            >
              <.icon name="hero-arrow-right-solid" class="nudge-icon" />
            </button>
          </div>
          <div class="nudge-row">
            <button
              type="button"
              class="nudge-btn"
              phx-click="nudge"
              phx-value-direction="down"
              phx-value-amount="5"
              aria-label="下に移動"
            >
              <.icon name="hero-arrow-down-solid" class="nudge-icon" />
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
