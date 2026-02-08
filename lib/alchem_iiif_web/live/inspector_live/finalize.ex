defmodule AlchemIiifWeb.InspectorLive.Finalize do
  @moduledoc """
  ウィザード Step 4: ファイナライズ画面。
  PTIF生成、メタデータのDB保存、IIIF Manifest の登録を行います。
  """
  use AlchemIiifWeb, :live_view

  alias AlchemIiif.Ingestion
  alias AlchemIiif.Ingestion.ImageProcessor
  alias AlchemIiif.IIIF.Manifest
  alias AlchemIiif.Repo

  @impl true
  def mount(%{"image_id" => image_id}, _session, socket) do
    extracted_image = Ingestion.get_extracted_image!(image_id)

    {:ok,
     socket
     |> assign(:page_title, "保存の確認")
     |> assign(:current_step, 4)
     |> assign(:extracted_image, extracted_image)
     |> assign(:processing, false)
     |> assign(:completed, false)
     |> assign(:error_message, nil)
     |> assign(:manifest_identifier, nil)}
  end

  @impl true
  def handle_event("confirm_save", _params, socket) do
    socket = assign(socket, :processing, true)
    extracted_image = socket.assigns.extracted_image

    # PTIF出力先
    ptif_dir = Path.join(["priv", "static", "iiif_images"])
    File.mkdir_p!(ptif_dir)

    # 一意の識別子を生成
    identifier = "img-#{extracted_image.id}-#{:rand.uniform(99999)}"
    ptif_path = Path.join(ptif_dir, "#{identifier}.tif")

    # クロップデータがある場合はクロップ→PTIF、ない場合は直接PTIF
    result =
      if extracted_image.geometry do
        # クロップ画像を一時ファイルに保存
        cropped_path = Path.join(ptif_dir, "#{identifier}_cropped.png")

        with :ok <-
               ImageProcessor.crop_image(
                 extracted_image.image_path,
                 extracted_image.geometry,
                 cropped_path
               ),
             :ok <- ImageProcessor.generate_ptif(cropped_path, ptif_path) do
          # 一時クロップファイルを削除
          File.rm(cropped_path)
          :ok
        end
      else
        ImageProcessor.generate_ptif(extracted_image.image_path, ptif_path)
      end

    case result do
      :ok ->
        # ExtractedImage を更新
        {:ok, _image} =
          Ingestion.update_extracted_image(extracted_image, %{ptif_path: ptif_path})

        # IIIF Manifest レコードを作成
        {:ok, _manifest} =
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

        {:noreply,
         socket
         |> assign(:processing, false)
         |> assign(:completed, true)
         |> assign(:manifest_identifier, identifier)
         |> put_flash(:info, "図版の保存が完了しました！")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:processing, false)
         |> assign(:error_message, "処理中にエラーが発生しました: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={4} />

      <div class="finalize-area">
        <%= if @completed do %>
          <%!-- 完了画面 --%>
          <div class="success-card">
            <span class="success-icon">✅</span>
            <h2 class="section-title">保存が完了しました！</h2>
            <p class="section-description">
              図版が正常に処理され、IIIF形式で保存されました。
            </p>

            <div class="result-info">
              <div class="info-item">
                <span class="info-label">識別子:</span>
                <code class="info-value">{@manifest_identifier}</code>
              </div>
              <div class="info-item">
                <span class="info-label">Manifest URL:</span>
                <a href={"/iiif/manifest/#{@manifest_identifier}"} class="info-link" target="_blank">
                  /iiif/manifest/{@manifest_identifier}
                </a>
              </div>
            </div>

            <div class="action-bar">
              <.link navigate={~p"/inspector"} class="btn-primary btn-large">
                📤 新しいPDFをアップロード
              </.link>
            </div>
          </div>
        <% else %>
          <%!-- 確認画面 --%>
          <h2 class="section-title">保存内容の確認</h2>
          <p class="section-description">
            以下の内容で図版を保存します。問題がなければ「保存する」を押してください。
          </p>

          <div class="confirm-card">
            <div class="confirm-item">
              <span class="confirm-label">📄 ページ番号:</span>
              <span class="confirm-value">ページ {@extracted_image.page_number}</span>
            </div>

            <%= if @extracted_image.caption do %>
              <div class="confirm-item">
                <span class="confirm-label">📝 キャプション:</span>
                <span class="confirm-value">{@extracted_image.caption}</span>
              </div>
            <% end %>

            <%= if @extracted_image.label do %>
              <div class="confirm-item">
                <span class="confirm-label">🏷️ ラベル:</span>
                <span class="confirm-value">{@extracted_image.label}</span>
              </div>
            <% end %>

            <%= if @extracted_image.geometry do %>
              <div class="confirm-item">
                <span class="confirm-label">✂️ クロップ範囲:</span>
                <span class="confirm-value">
                  X:{@extracted_image.geometry["x"]},
                  Y:{@extracted_image.geometry["y"]},
                  W:{@extracted_image.geometry["width"]},
                  H:{@extracted_image.geometry["height"]}
                </span>
              </div>
            <% end %>
          </div>

          <%= if @error_message do %>
            <div class="error-message" role="alert">
              <span class="error-icon">⚠️</span>
              {@error_message}
            </div>
          <% end %>

          <div class="action-bar">
            <.link
              navigate={~p"/inspector/crop/#{@extracted_image.id}"}
              class="btn-secondary btn-large"
            >
              ← 戻る
            </.link>

            <button
              type="button"
              class="btn-primary btn-large btn-confirm"
              phx-click="confirm_save"
              disabled={@processing}
            >
              <%= if @processing do %>
                <span class="spinner"></span> 処理中...
              <% else %>
                💾 保存する
              <% end %>
            </button>
          </div>
        <% end %>
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
