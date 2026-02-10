defmodule AlchemIiifWeb.Admin.ReviewLive do
  @moduledoc """
  Admin Review Dashboard LiveView。
  公開前の最終品質ゲートとして、status == "pending_review" の画像を
  管理者がレビューし、承認または差し戻しを行う画面です。

  ## 機能
  - 大型カードグリッドで pending_review 画像を一覧表示
  - Nudge Inspector（サイドパネル）でフル画像を確認
  - Validation Badge で技術的妥当性を視覚的に表示
  - Optimistic UI: 承認時にカードがフェードアウトアニメーション

  ## 認知アクセシビリティ対応
  - 大きなボタン（最小 60×60px）
  - 高コントラスト色使い
  - 明確な状態遷移フィードバック
  """
  use AlchemIiifWeb, :live_view

  alias AlchemIiif.Ingestion

  @impl true
  def mount(_params, _session, socket) do
    pending_images = Ingestion.list_pending_review_images()

    # 各画像にバリデーション結果を付与
    images_with_validation =
      Enum.map(pending_images, fn image ->
        validation = Ingestion.validate_image_data(image)
        %{image: image, validation: validation}
      end)

    {:ok,
     socket
     |> assign(:page_title, "Admin Review Dashboard")
     |> assign(:pending_images, images_with_validation)
     |> assign(:pending_count, length(images_with_validation))
     |> assign(:selected_image, nil)
     |> assign(:show_reject_modal, false)
     |> assign(:reject_note, "")
     |> assign(:reject_target_id, nil)
     |> assign(:fading_ids, MapSet.new())}
  end

  # --- イベントハンドラ ---

  @impl true
  def handle_event("select_image", %{"id" => id}, socket) do
    image_id = String.to_integer(id)

    selected =
      Enum.find(socket.assigns.pending_images, fn item ->
        item.image.id == image_id
      end)

    {:noreply, assign(socket, :selected_image, selected)}
  end

  @impl true
  def handle_event("close_inspector", _params, socket) do
    {:noreply, assign(socket, :selected_image, nil)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    image = Ingestion.get_extracted_image!(id)

    case Ingestion.approve_and_publish(image) do
      {:ok, _updated} ->
        # Optimistic UI: フェードアウト対象に追加
        image_id = String.to_integer(id)
        fading_ids = MapSet.put(socket.assigns.fading_ids, image_id)

        # 500ms 後にリストから削除（アニメーション完了後）
        Process.send_after(self(), {:remove_faded, image_id}, 500)

        {:noreply,
         socket
         |> assign(:fading_ids, fading_ids)
         |> close_inspector_if_selected(image_id)
         |> put_flash(:info, "「#{image.label || "名称未設定"}」を公開しました！ 🎉")}

      {:error, :invalid_status_transition} ->
        {:noreply, put_flash(socket, :error, "この画像は承認できません。")}
    end
  end

  @impl true
  def handle_event("open_reject_modal", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:show_reject_modal, true)
     |> assign(:reject_target_id, id)
     |> assign(:reject_note, "")}
  end

  @impl true
  def handle_event("close_reject_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_reject_modal, false)
     |> assign(:reject_target_id, nil)
     |> assign(:reject_note, "")}
  end

  @impl true
  def handle_event("update_reject_note", %{"note" => note}, socket) do
    {:noreply, assign(socket, :reject_note, note)}
  end

  @impl true
  def handle_event("confirm_reject", _params, socket) do
    id = socket.assigns.reject_target_id
    note = socket.assigns.reject_note
    image = Ingestion.get_extracted_image!(id)

    case Ingestion.reject_to_draft_with_note(image, note) do
      {:ok, _updated} ->
        # リストを再取得
        pending_images = Ingestion.list_pending_review_images()

        images_with_validation =
          Enum.map(pending_images, fn img ->
            validation = Ingestion.validate_image_data(img)
            %{image: img, validation: validation}
          end)

        image_id = String.to_integer(id)

        {:noreply,
         socket
         |> assign(:pending_images, images_with_validation)
         |> assign(:pending_count, length(images_with_validation))
         |> assign(:show_reject_modal, false)
         |> assign(:reject_target_id, nil)
         |> assign(:reject_note, "")
         |> close_inspector_if_selected(image_id)
         |> put_flash(:info, "「#{image.label || "名称未設定"}」を差し戻しました。")}

      {:error, :invalid_status_transition} ->
        {:noreply,
         socket
         |> assign(:show_reject_modal, false)
         |> put_flash(:error, "この画像は差し戻しできません。")}
    end
  end

  @impl true
  def handle_info({:remove_faded, image_id}, socket) do
    # フェードアウト完了: リストから削除
    updated_images =
      Enum.reject(socket.assigns.pending_images, fn item ->
        item.image.id == image_id
      end)

    fading_ids = MapSet.delete(socket.assigns.fading_ids, image_id)

    {:noreply,
     socket
     |> assign(:pending_images, updated_images)
     |> assign(:pending_count, length(updated_images))
     |> assign(:fading_ids, fading_ids)}
  end

  # --- レンダリング ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="admin-review-container">
      <%!-- ヘッダー --%>
      <div class="admin-review-header">
        <h1 class="section-title">🛡️ Admin Review Dashboard</h1>
        <p class="section-description">
          公開前の最終品質チェックです。画像とメタデータを確認し、承認または差し戻しを行います。
        </p>
        <div class="review-stats">
          <span class="stats-badge stats-badge-pending">
            ⏳ レビュー待ち: {@pending_count} 件
          </span>
        </div>
      </div>

      <%!-- メインコンテンツ: グリッド + インスペクター --%>
      <div class={"review-layout #{if @selected_image, do: "inspector-open", else: ""}"}>
        <%!-- カードグリッド --%>
        <div class="review-grid-area">
          <%= if @pending_images == [] do %>
            <div class="no-results">
              <span class="no-results-icon">✅</span>
              <p class="section-description">
                レビュー待ちの図版はありません。すべて処理済みです！
              </p>
            </div>
          <% else %>
            <div class="review-grid">
              <%= for item <- @pending_images do %>
                <div
                  id={"review-card-#{item.image.id}"}
                  class={"review-card #{if @selected_image && @selected_image.image.id == item.image.id, do: "selected", else: ""} #{if MapSet.member?(@fading_ids, item.image.id), do: "card-fade-out", else: ""}"}
                  phx-click="select_image"
                  phx-value-id={item.image.id}
                  role="button"
                  tabindex="0"
                  aria-label={"「#{item.image.label || "名称未設定"}」を選択"}
                >
                  <%!-- Validation Badge --%>
                  <div class="validation-badge-container">
                    <%= case item.validation do %>
                      <% {:ok, :valid} -> %>
                        <span class="validation-badge badge-valid" title="技術的に有効">
                          ✓ OK
                        </span>
                      <% {:error, _issues} -> %>
                        <span
                          class="validation-badge badge-warning"
                          title="確認が必要な項目があります"
                        >
                          ⚠ 要確認
                        </span>
                    <% end %>
                  </div>

                  <%!-- 画像サムネイル --%>
                  <div class="review-card-image-container">
                    <img
                      src={image_thumbnail_url(item.image)}
                      alt={item.image.caption || "図版"}
                      class="review-card-image"
                      loading="lazy"
                    />
                  </div>

                  <%!-- メタデータ --%>
                  <div class="review-card-body">
                    <h3 class="review-card-title">{item.image.label || "名称未設定"}</h3>
                    <div class="review-card-meta">
                      <%= if item.image.site do %>
                        <span class="meta-tag">📍 {item.image.site}</span>
                      <% end %>
                      <%= if item.image.page_number do %>
                        <span class="meta-tag">📄 P.{item.image.page_number}</span>
                      <% end %>
                      <%= if item.image.period do %>
                        <span class="meta-tag">⏳ {item.image.period}</span>
                      <% end %>
                    </div>
                  </div>

                  <%!-- カードアクションボタン --%>
                  <div class="review-card-actions">
                    <button
                      type="button"
                      class="btn-approve btn-large"
                      phx-click="approve"
                      phx-value-id={item.image.id}
                      aria-label={"「#{item.image.label || "名称未設定"}」を承認して公開"}
                    >
                      ✅ 承認
                    </button>
                    <button
                      type="button"
                      class="btn-reject btn-large"
                      phx-click="open_reject_modal"
                      phx-value-id={item.image.id}
                      aria-label={"「#{item.image.label || "名称未設定"}」を差し戻し"}
                    >
                      ↩️ 差し戻し
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Nudge Inspector サイドパネル --%>
        <%= if @selected_image do %>
          <div class="review-inspector" role="complementary" aria-label="画像インスペクター">
            <div class="inspector-header">
              <h2 class="inspector-title">🔍 インスペクター</h2>
              <button
                type="button"
                class="inspector-close-btn"
                phx-click="close_inspector"
                aria-label="インスペクターを閉じる"
              >
                ✕
              </button>
            </div>

            <%!-- フル画像 --%>
            <div class="inspector-image-container">
              <img
                src={image_full_url(@selected_image.image)}
                alt={@selected_image.image.caption || "図版"}
                class="inspector-full-image"
              />
            </div>

            <%!-- 詳細メタデータ --%>
            <div class="inspector-details">
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">ラベル</span>
                <span class="inspector-detail-value">{@selected_image.image.label || "—"}</span>
              </div>
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">キャプション</span>
                <span class="inspector-detail-value">{@selected_image.image.caption || "—"}</span>
              </div>
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">遺跡名</span>
                <span class="inspector-detail-value">{@selected_image.image.site || "—"}</span>
              </div>
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">時代</span>
                <span class="inspector-detail-value">{@selected_image.image.period || "—"}</span>
              </div>
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">遺物種別</span>
                <span class="inspector-detail-value">
                  {@selected_image.image.artifact_type || "—"}
                </span>
              </div>
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">ページ番号</span>
                <span class="inspector-detail-value">P.{@selected_image.image.page_number}</span>
              </div>
              <div class="inspector-detail-item">
                <span class="inspector-detail-label">PTIF</span>
                <span class="inspector-detail-value inspector-path">
                  {@selected_image.image.ptif_path || "—"}
                </span>
              </div>

              <%!-- Validation Badge 詳細 --%>
              <div class="inspector-validation">
                <%= case @selected_image.validation do %>
                  <% {:ok, :valid} -> %>
                    <div class="validation-detail valid">
                      <span class="validation-icon">✅</span>
                      <span>全項目OK — 画像・メタデータは技術的に有効です</span>
                    </div>
                  <% {:error, issues} -> %>
                    <div class="validation-detail warning">
                      <span class="validation-icon">⚠️</span>
                      <div>
                        <span>以下の項目を確認してください:</span>
                        <ul class="validation-issues">
                          <%= for issue <- issues do %>
                            <li>{validation_issue_label(issue)}</li>
                          <% end %>
                        </ul>
                      </div>
                    </div>
                <% end %>
              </div>
            </div>

            <%!-- インスペクターアクション --%>
            <div class="inspector-actions">
              <button
                type="button"
                class="btn-approve btn-large inspector-action-btn"
                phx-click="approve"
                phx-value-id={@selected_image.image.id}
              >
                ✅ 承認して公開
              </button>
              <button
                type="button"
                class="btn-reject btn-large inspector-action-btn"
                phx-click="open_reject_modal"
                phx-value-id={@selected_image.image.id}
              >
                ↩️ 差し戻し
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- 差し戻しモーダル --%>
      <%= if @show_reject_modal do %>
        <div class="modal-overlay" phx-click="close_reject_modal">
          <div class="modal-content" phx-click-away="close_reject_modal">
            <h3 class="modal-title">↩️ 差し戻し理由</h3>
            <p class="modal-description">
              差し戻しの理由を記入してください（任意）。
            </p>
            <textarea
              id="reject-note-input"
              class="form-input reject-note-textarea"
              placeholder="例: メタデータに修正が必要です"
              phx-keyup="update_reject_note"
              phx-value-note={@reject_note}
              rows="4"
            >{@reject_note}</textarea>
            <div class="modal-actions">
              <button
                type="button"
                class="btn-secondary btn-large"
                phx-click="close_reject_modal"
              >
                キャンセル
              </button>
              <button
                type="button"
                class="btn-reject btn-large"
                phx-click="confirm_reject"
              >
                ↩️ 差し戻しを実行
              </button>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- フッターナビゲーション --%>
      <div class="admin-review-footer">
        <.link navigate={~p"/lab"} class="btn-secondary btn-large">
          ← Lab に戻る
        </.link>
        <.link navigate={~p"/gallery"} class="btn-secondary btn-large">
          🏛️ ギャラリーを確認
        </.link>
      </div>
    </div>
    """
  end

  # --- プライベート関数 ---

  # インスペクターが選択中の画像なら閉じる
  defp close_inspector_if_selected(socket, image_id) do
    if socket.assigns.selected_image &&
         socket.assigns.selected_image.image.id == image_id do
      assign(socket, :selected_image, nil)
    else
      socket
    end
  end

  # サムネイル URL の生成
  defp image_thumbnail_url(image) do
    case image.iiif_manifest do
      nil ->
        image.image_path
        |> String.replace_leading("priv/static/", "/")

      manifest ->
        "/iiif/image/#{manifest.identifier}/full/400,/0/default.jpg"
    end
  end

  # フル画像 URL の生成
  defp image_full_url(image) do
    case image.iiif_manifest do
      nil ->
        image.image_path
        |> String.replace_leading("priv/static/", "/")

      manifest ->
        "/iiif/image/#{manifest.identifier}/full/max/0/default.jpg"
    end
  end

  # バリデーション項目のラベル
  defp validation_issue_label(:image_file), do: "画像ファイルパスが未設定です"
  defp validation_issue_label(:ptif_file), do: "PTIF ファイルパスが未設定です"
  defp validation_issue_label(:geometry), do: "クロップ座標が未設定です"
  defp validation_issue_label(:metadata), do: "ラベルが未設定です"
  defp validation_issue_label(other), do: "#{other} に問題があります"
end
