defmodule AlchemIiifWeb.InspectorLive.Label do
  @moduledoc """
  ウィザード Step 4: ラベリング（メタデータ入力）画面。
  1タスク1画面の原則に基づき、メタデータ入力のみに集中します。
  Auto-Save と Undo 機能を搭載。
  """
  use AlchemIiifWeb, :live_view

  import AlchemIiifWeb.WizardComponents

  alias AlchemIiif.Ingestion

  @impl true
  def mount(%{"image_id" => image_id}, _session, socket) do
    extracted_image = Ingestion.get_extracted_image!(image_id)

    # 画像のURLを生成（プレビュー用）
    image_url =
      extracted_image.image_path
      |> String.replace_leading("priv/static/", "/")

    {:ok,
     socket
     |> assign(:page_title, "ラベリング")
     |> assign(:current_step, 4)
     |> assign(:extracted_image, extracted_image)
     |> assign(:image_url, image_url)
     |> assign(:caption, extracted_image.caption || "")
     |> assign(:label, extracted_image.label || "")
     |> assign(:site, extracted_image.site || "")
     |> assign(:period, extracted_image.period || "")
     |> assign(:artifact_type, extracted_image.artifact_type || "")
     |> assign(:undo_stack, [])
     |> assign(:save_state, :idle)}
  end

  # --- メタデータ更新イベント ---

  @impl true
  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    # 現在の値を Undo スタックに保存
    current_snapshot = take_snapshot(socket)
    undo_stack = [current_snapshot | socket.assigns.undo_stack] |> Enum.take(20)

    field_atom = String.to_existing_atom(field)

    {:noreply,
     socket
     |> assign(field_atom, value)
     |> assign(:undo_stack, undo_stack)
     |> auto_save_field(field, value)}
  end

  @impl true
  def handle_event("undo", _params, socket) do
    case socket.assigns.undo_stack do
      [previous | rest] ->
        {:noreply,
         socket
         |> assign(:caption, previous.caption)
         |> assign(:label, previous.label)
         |> assign(:site, previous.site)
         |> assign(:period, previous.period)
         |> assign(:artifact_type, previous.artifact_type)
         |> assign(:undo_stack, rest)
         |> auto_save_all(previous)}

      [] ->
        {:noreply, put_flash(socket, :info, "元に戻す操作はありません")}
    end
  end

  @impl true
  def handle_event("proceed_to_finalize", _params, socket) do
    # 全メタデータを保存してファイナライズ画面に遷移
    {:ok, _updated_image} =
      Ingestion.update_extracted_image(socket.assigns.extracted_image, %{
        caption: socket.assigns.caption,
        label: socket.assigns.label,
        site: socket.assigns.site,
        period: socket.assigns.period,
        artifact_type: socket.assigns.artifact_type
      })

    {:noreply, push_navigate(socket, to: ~p"/lab/finalize/#{socket.assigns.extracted_image.id}")}
  end

  @impl true
  def handle_info(:auto_save_complete, socket) do
    {:noreply, assign(socket, :save_state, :saved)}
  end

  # --- プライベート関数 ---

  defp take_snapshot(socket) do
    %{
      caption: socket.assigns.caption,
      label: socket.assigns.label,
      site: socket.assigns.site,
      period: socket.assigns.period,
      artifact_type: socket.assigns.artifact_type
    }
  end

  defp auto_save_field(socket, field, value) do
    socket = assign(socket, :save_state, :saving)
    extracted_image = socket.assigns.extracted_image
    lv_pid = self()

    Task.start(fn ->
      Ingestion.update_extracted_image(extracted_image, %{
        String.to_existing_atom(field) => value
      })

      send(lv_pid, :auto_save_complete)
    end)

    socket
  end

  defp auto_save_all(socket, snapshot) do
    socket = assign(socket, :save_state, :saving)
    extracted_image = socket.assigns.extracted_image
    lv_pid = self()

    Task.start(fn ->
      Ingestion.update_extracted_image(extracted_image, snapshot)
      send(lv_pid, :auto_save_complete)
    end)

    socket
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={@current_step} />

      <div class="label-area">
        <h2 class="section-title">🏷️ 図版の情報を入力してください</h2>
        <p class="section-description">
          各フィールドに情報を入力してください。入力内容は自動的に保存されます。
        </p>

        <%!-- Auto-Save ステータス --%>
        <.auto_save_indicator state={@save_state} />

        <%!-- プレビュー画像（サムネイル） --%>
        <div class="label-preview">
          <img src={@image_url} alt="選択した図版" class="label-preview-image" />
        </div>

        <%!-- メタデータ入力フォーム --%>
        <div class="metadata-form">
          <div class="form-group">
            <label for="caption-input" class="form-label">📝 キャプション（図の説明）</label>
            <input
              type="text"
              id="caption-input"
              class="form-input form-input-large"
              value={@caption}
              phx-blur="update_field"
              phx-value-field="caption"
              phx-value-value={@caption}
              placeholder="例: 第3図 土器出土状況"
              name="caption"
            />
          </div>

          <div class="form-group">
            <label for="label-input" class="form-label">🏷️ ラベル（短い識別名）</label>
            <input
              type="text"
              id="label-input"
              class="form-input form-input-large"
              value={@label}
              phx-blur="update_field"
              phx-value-field="label"
              phx-value-value={@label}
              placeholder="例: fig-003"
              name="label"
            />
          </div>

          <div class="form-group">
            <label for="site-input" class="form-label">📍 遺跡名（任意）</label>
            <input
              type="text"
              id="site-input"
              class="form-input form-input-large"
              value={@site}
              phx-blur="update_field"
              phx-value-field="site"
              phx-value-value={@site}
              placeholder="例: 吉野ヶ里遺跡"
              name="site"
            />
          </div>

          <div class="form-group">
            <label for="period-input" class="form-label">⏳ 時代（任意）</label>
            <input
              type="text"
              id="period-input"
              class="form-input form-input-large"
              value={@period}
              phx-blur="update_field"
              phx-value-field="period"
              phx-value-value={@period}
              placeholder="例: 縄文時代"
              name="period"
            />
          </div>

          <div class="form-group">
            <label for="artifact-type-input" class="form-label">🏺 遺物種別（任意）</label>
            <input
              type="text"
              id="artifact-type-input"
              class="form-input form-input-large"
              value={@artifact_type}
              phx-blur="update_field"
              phx-value-field="artifact_type"
              phx-value-value={@artifact_type}
              placeholder="例: 土器"
              name="artifact_type"
            />
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
            navigate={~p"/lab/crop/#{@extracted_image.id}"}
            class="btn-secondary btn-large"
          >
            ← 戻る
          </.link>

          <button
            type="button"
            class="btn-primary btn-large"
            phx-click="proceed_to_finalize"
          >
            次へ: 保存 →
          </button>
        </div>
      </div>
    </div>
    """
  end
end
