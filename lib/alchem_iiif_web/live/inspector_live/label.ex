defmodule AlchemIiifWeb.InspectorLive.Label do
  @moduledoc """
  ウィザード Step 4: ラベリング（メタデータ入力）画面。
  1タスク1画面の原則に基づき、メタデータ入力のみに集中します。
  Auto-Save と Undo 機能を搭載。
  """
  use AlchemIiifWeb, :live_view

  import AlchemIiifWeb.WizardComponents

  alias AlchemIiif.Ingestion
  alias AlchemIiif.Ingestion.ImageProcessor

  @editable_fields %{
    "caption" => :caption,
    "label" => :label,
    "site" => :site,
    "period" => :period,
    "artifact_type" => :artifact_type,
    "material" => :material
  }

  @impl true
  def mount(%{"image_id" => image_id}, _session, socket) do
    current_user = socket.assigns.current_user

    extracted_image =
      try do
        Ingestion.get_extracted_image!(image_id, current_user)
      rescue
        Ecto.NoResultsError -> nil
      end

    if is_nil(extracted_image) do
      {:ok,
       socket
       |> put_flash(:error, "指定された画像が見つかりません")
       |> push_navigate(to: ~p"/lab")}
    else
      pdf_source = Ingestion.get_pdf_source!(extracted_image.pdf_source_id, current_user)

      # 画像のURLを生成（プレビュー用）
      image_url = ~p"/lab/media/images/#{extracted_image.id}/source"

      # 元画像の寸法を取得（Vix はヘッダーのみ遅延読み込み）
      {orig_w, orig_h} = read_source_dimensions(extracted_image.image_path)

      # ジオメトリからプレビュー用データを構築
      geo = extracted_image.geometry
      {polygon_points, bbox} = extract_preview_data(geo)
      polygon_fill = polygon_fill_color(extracted_image.image_path, geo)

      {:ok,
       socket
       |> assign(:page_title, "ラベリング")
       |> assign(:current_step, 4)
       |> assign(:extracted_image, extracted_image)
       |> assign(:pdf_source, pdf_source)
       |> assign(:image_url, image_url)
       |> assign(:orig_w, orig_w)
       |> assign(:orig_h, orig_h)
       |> assign(:geo, geo)
       |> assign(:has_crop, geo != nil)
       |> assign(:polygon_points, polygon_points)
       |> assign(:bbox, bbox)
       |> assign(:polygon_fill, polygon_fill)
       |> assign(:caption, extracted_image.caption || "")
       |> assign(:label, extracted_image.label || "")
       |> assign(:site, extracted_image.site || "")
       |> assign(:period, extracted_image.period || "")
       |> assign(:artifact_type, extracted_image.artifact_type || "")
       |> assign(:material, extracted_image.material || "")
       |> assign(:undo_stack, [])
       |> assign(:pre_edit_snapshot, nil)
       |> assign(:duplicate_record, check_duplicate_label(extracted_image))
       |> assign(:validation_errors, %{})
       |> assign(:save_state, :idle)
       |> assign(
         :is_rejected,
         extracted_image.status == "rejected" || pdf_source.workflow_status == "returned"
       )}
    end
  end

  # --- メタデータ更新イベント ---

  # phx-change: フォーム入力のリアルタイムバリデーション
  @impl true
  def handle_event("validate_metadata", params, socket) do
    # 編集開始時のスナップショットを保存（Undo 用）
    socket =
      if is_nil(socket.assigns.pre_edit_snapshot) do
        assign(socket, :pre_edit_snapshot, take_snapshot(socket))
      else
        socket
      end

    # フォームの実入力値で assigns を更新
    socket =
      socket
      |> assign(:caption, Map.get(params, "caption", socket.assigns.caption))
      |> assign(:label, Map.get(params, "label", socket.assigns.label))
      |> assign(:site, Map.get(params, "site", socket.assigns.site))
      |> assign(:period, Map.get(params, "period", socket.assigns.period))
      |> assign(:artifact_type, Map.get(params, "artifact_type", socket.assigns.artifact_type))
      |> assign(:material, Map.get(params, "material", socket.assigns.material))

    # 変更されたフィールドのバリデーション
    target = List.first(params["_target"] || [])

    socket =
      if target,
        do: run_inline_validation(socket, target, Map.get(params, target, "")),
        else: socket

    # label/site 変更時は重複チェック
    socket =
      if target in ["label", "site"] do
        duplicate =
          Ingestion.find_duplicate_label(
            socket.assigns.site,
            socket.assigns.label,
            socket.assigns.extracted_image.id
          )

        assign(socket, :duplicate_record, duplicate)
      else
        socket
      end

    {:noreply, socket}
  end

  # phx-blur: フィールド離脱時に自動保存（Undo スナップショット確定）
  @impl true
  def handle_event("blur_save_field", %{"field" => field}, socket) do
    with {:ok, field_atom} <- field_atom(field) do
      blur_save_field(socket, field, field_atom)
    else
      :error -> {:noreply, socket}
    end
  end

  # レガシー互換: テストから呼ばれる update_field イベント
  @impl true
  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    with {:ok, field_atom} <- field_atom(field) do
      current_snapshot = take_snapshot(socket)
      undo_stack = [current_snapshot | socket.assigns.undo_stack] |> Enum.take(20)

      socket =
        socket
        |> assign(field_atom, value)
        |> assign(:undo_stack, undo_stack)
        |> auto_save_field(field, value)

      # インラインバリデーション
      socket = run_inline_validation(socket, field, value)

      # label/site 変更時は重複チェック
      socket =
        if field in ["label", "site"] do
          duplicate =
            Ingestion.find_duplicate_label(
              socket.assigns.site,
              socket.assigns.label,
              socket.assigns.extracted_image.id
            )

          assign(socket, :duplicate_record, duplicate)
        else
          socket
        end

      {:noreply, socket}
    else
      :error -> {:noreply, socket}
    end
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
         |> assign(:material, previous.material)
         |> assign(:undo_stack, rest)
         |> auto_save_all(previous)}

      [] ->
        {:noreply, put_flash(socket, :info, "元に戻す操作はありません")}
    end
  end

  @impl true
  def handle_event("save", %{"action" => action}, socket) do
    # "finish" 時に重複ラベルがあればブロック
    if action == "finish" && socket.assigns.duplicate_record do
      {:noreply, put_flash(socket, :error, "⚠️ 重複ラベルがあります。ラベルを変更するか、既存レコードを更新してください。")}
    else
      do_save(socket, action)
    end
  end

  @impl true
  def handle_event("merge_existing", _params, socket) do
    # 重複レコードの編集画面にナビゲート
    case socket.assigns.duplicate_record do
      nil ->
        {:noreply, put_flash(socket, :info, "重複レコードはありません")}

      dup ->
        {:noreply,
         socket
         |> put_flash(:info, "既存レコード ##{dup.id} を編集します")
         |> push_navigate(to: ~p"/lab/label/#{dup.id}")}
    end
  end

  @impl true
  def handle_info(:auto_save_complete, socket) do
    {:noreply, assign(socket, :save_state, :saved)}
  end

  @impl true
  def handle_info({:auto_save_complete, updated_image}, socket) do
    {:noreply,
     socket
     |> assign(:save_state, :saved)
     |> assign(:extracted_image, updated_image)}
  end

  @impl true
  def handle_info({:auto_save_error, errors}, socket) do
    {:noreply,
     socket
     |> assign(:save_state, :idle)
     |> assign(:validation_errors, Map.merge(socket.assigns.validation_errors, errors))}
  end

  @impl true
  def handle_info(:stale_detected, socket) do
    {:noreply,
     put_flash(socket, :error, "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected).")}
  end

  # --- プライベート関数 ---

  defp blur_save_field(socket, field, field_atom) do
    # 編集前スナップショットを Undo スタックに追加
    {socket, undo_stack} =
      case socket.assigns.pre_edit_snapshot do
        nil ->
          {socket, socket.assigns.undo_stack}

        snapshot ->
          stack = [snapshot | socket.assigns.undo_stack] |> Enum.take(20)
          {assign(socket, :pre_edit_snapshot, nil), stack}
      end

    value = Map.get(socket.assigns, field_atom)

    socket =
      socket
      |> assign(:undo_stack, undo_stack)
      |> auto_save_field(field, value)

    {:noreply, socket}
  end

  defp take_snapshot(socket) do
    %{
      caption: socket.assigns.caption,
      label: socket.assigns.label,
      site: socket.assigns.site,
      period: socket.assigns.period,
      artifact_type: socket.assigns.artifact_type,
      material: socket.assigns.material
    }
  end

  defp auto_save_field(socket, field, value) do
    with {:ok, field_atom} <- field_atom(field) do
      do_auto_save_field(socket, field, field_atom, value)
    else
      :error -> socket
    end
  end

  defp do_auto_save_field(socket, field, field_atom, value) do
    # 保存前の文字数制限チェック（非同期保存を試みる前にブロック）
    max_len =
      case field do
        "caption" -> 1000
        "material" -> 100
        _ -> 30
      end

    if field in ["site", "period", "artifact_type", "caption", "material"] and
         String.length(to_string(value)) > max_len do
      errors =
        Map.put(
          socket.assigns.validation_errors,
          field_atom,
          "#{max_len}文字以内で入力してください"
        )

      assign(socket, validation_errors: errors, save_state: :idle)
    else
      socket = assign(socket, :save_state, :saving)
      extracted_image = socket.assigns.extracted_image
      lv_pid = self()

      Task.start(fn ->
        case Ingestion.update_extracted_image(extracted_image, %{
               field_atom => value
             }) do
          {:ok, updated} ->
            send(lv_pid, {:auto_save_complete, updated})

          {:error, :stale} ->
            send(lv_pid, :stale_detected)

          {:error, %Ecto.Changeset{} = changeset} ->
            errors = extract_changeset_field_errors(changeset)
            send(lv_pid, {:auto_save_error, errors})

          {:error, _} ->
            send(lv_pid, :auto_save_complete)
        end
      end)

      socket
    end
  end

  defp field_atom(field) do
    case Map.fetch(@editable_fields, field) do
      {:ok, field_atom} -> {:ok, field_atom}
      :error -> :error
    end
  end

  defp auto_save_all(socket, snapshot) do
    socket = assign(socket, :save_state, :saving)
    extracted_image = socket.assigns.extracted_image
    lv_pid = self()

    Task.start(fn ->
      case Ingestion.update_extracted_image(extracted_image, snapshot) do
        {:ok, updated} ->
          send(lv_pid, {:auto_save_complete, updated})

        {:error, :stale} ->
          send(lv_pid, :stale_detected)

        {:error, %Ecto.Changeset{} = changeset} ->
          errors = extract_changeset_field_errors(changeset)
          send(lv_pid, {:auto_save_error, errors})

        {:error, _} ->
          send(lv_pid, :auto_save_complete)
      end
    end)

    socket
  end

  # 全メタデータを一括保存する共通関数
  defp save_metadata(socket, extra_attrs) do
    base_attrs = %{
      caption: socket.assigns.caption,
      label: socket.assigns.label,
      site: socket.assigns.site,
      period: socket.assigns.period,
      artifact_type: socket.assigns.artifact_type,
      material: socket.assigns.material
    }

    Ingestion.update_extracted_image(
      socket.assigns.extracted_image,
      Map.merge(base_attrs, extra_attrs)
    )
  end

  # 保存ロジック（重複チェック通過後に呼ばれる）
  # 全アクション（finish / continue）で status を pending_review に昇格する
  defp do_save(socket, action) do
    cond do
      # バリデーションエラーがある場合は保存をブロック
      socket.assigns.validation_errors != %{} ->
        {:noreply, put_flash(socket, :error, "⚠️ 入力エラーがあります。修正してから保存してください。")}

      # geometry が nil の場合は保存をブロック
      is_nil(socket.assigns.extracted_image.geometry) and is_nil(socket.assigns.geo) ->
        {:noreply, put_flash(socket, :error, "⚠️ クロップ範囲が設定されていません。先にクロップ画面で範囲を指定してください。")}

      true ->
        process_save(socket, action)
    end
  end

  defp process_save(socket, action) do
    save_result = execute_save_operation(socket)
    handle_save_result(save_result, socket, action)
  end

  defp execute_save_operation(socket) do
    if socket.assigns.is_rejected do
      case save_metadata(socket, %{}) do
        {:ok, _} ->
          updated =
            Ingestion.get_extracted_image!(
              socket.assigns.extracted_image.id,
              socket.assigns.current_user
            )

          Ingestion.resubmit_image(updated)

        error ->
          error
      end
    else
      # 通常: 全保存パスで status: "pending_review" を強制設定
      save_metadata(socket, %{status: "pending_review"})
    end
  end

  defp handle_save_result({:ok, _updated}, socket, action) do
    # PTIF をバックグラウンド生成（全アクション共通）
    updated_image =
      Ingestion.get_extracted_image!(
        socket.assigns.extracted_image.id,
        socket.assigns.current_user
      )

    Task.start(fn ->
      AlchemIiif.Pipeline.generate_single_ptif(updated_image)
    end)

    {flash_msg, route} = determine_success_navigation(socket, action)

    {:noreply,
     socket
     |> put_flash(:info, flash_msg)
     |> push_navigate(to: route)}
  end

  defp handle_save_result({:error, :stale}, socket, _action) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "他ユーザーによって更新されました。ページをリロードしてください (Data conflict detected)."
     )}
  end

  defp handle_save_result({:error, changeset}, socket, _action) do
    errors = extract_changeset_field_errors(changeset)

    {:noreply,
     socket
     |> assign(:validation_errors, Map.merge(socket.assigns.validation_errors, errors))
     |> put_flash(:error, "保存に失敗しました。入力内容を確認してください。")}
  end

  defp determine_success_navigation(socket, action) do
    if socket.assigns.is_rejected do
      {"✅ 再提出しました！レビューをお待ちください。", ~p"/lab"}
    else
      case action do
        "continue" ->
          {"✅ レビューに提出しました！次の図版を選択してください。",
           ~p"/lab/browse/#{socket.assigns.extracted_image.pdf_source_id}"}

        _finish ->
          {"✅ 提出しました！高解像度レビュー用に画像を処理中です。", ~p"/lab"}
      end
    end
  end

  # 初期表示時の重複チェック
  defp check_duplicate_label(extracted_image) do
    Ingestion.find_duplicate_label(
      extracted_image.site,
      extracted_image.label,
      extracted_image.id
    )
  end

  # インラインバリデーション（入力時にエラーメッセージを表示）
  defp run_inline_validation(socket, field, value) do
    errors = validate_field(socket.assigns.validation_errors, field, value)
    assign(socket, :validation_errors, errors)
  end

  defp validate_field(errors, "label", value) do
    if value != "" and not Regex.match?(~r/^fig-\d+-\d+$/, value) do
      Map.put(errors, :label, "形式は 'fig-番号-番号' にしてください（例: fig-1-1）")
    else
      Map.delete(errors, :label)
    end
  end

  defp validate_field(errors, "site", value) do
    cond do
      String.length(value) > 30 ->
        Map.put(errors, :site, "30文字以内で入力してください")

      value != "" and not String.contains?(value, ["市", "町", "村"]) ->
        Map.put(errors, :site, "市町村名（市・町・村）を含めてください（例: 新潟市中野遺跡）")

      true ->
        Map.delete(errors, :site)
    end
  end

  defp validate_field(errors, "period", value) do
    if String.length(value) > 30 do
      Map.put(errors, :period, "30文字以内で入力してください")
    else
      Map.delete(errors, :period)
    end
  end

  defp validate_field(errors, "artifact_type", value) do
    if String.length(value) > 30 do
      Map.put(errors, :artifact_type, "30文字以内で入力してください")
    else
      Map.delete(errors, :artifact_type)
    end
  end

  defp validate_field(errors, "caption", value) do
    if String.length(value) > 1000 do
      Map.put(errors, :caption, "1000文字以内で入力してください")
    else
      Map.delete(errors, :caption)
    end
  end

  defp validate_field(errors, "material", value) do
    if String.length(value) > 100 do
      Map.put(errors, :material, "100文字以内で入力してください")
    else
      Map.delete(errors, :material)
    end
  end

  defp validate_field(errors, _field, _value), do: errors

  # changeset からフィールドごとのエラーメッセージを抽出
  defp extract_changeset_field_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, [msg | _]} -> {field, msg} end)
    |> Map.new()
  end

  # 元画像の寸法を Vix で読み取る（ヘッダーのみ遅延読み込みなので軽量）
  defp read_source_dimensions(image_path) do
    case ImageProcessor.get_image_dimensions(image_path) do
      {:ok, %{width: w, height: h}} -> {w, h}
      _error -> {0, 0}
    end
  end

  # ジオメトリデータからプレビュー用のポリゴン頂点とバウンディングボックスを抽出
  defp extract_preview_data(%{"points" => points}) when is_list(points) and length(points) >= 3 do
    xs = Enum.map(points, fn p -> safe_int(p["x"]) end)
    ys = Enum.map(points, fn p -> safe_int(p["y"]) end)

    min_x = Enum.min(xs)
    min_y = Enum.min(ys)
    max_x = Enum.max(xs)
    max_y = Enum.max(ys)

    bbox = %{
      x: min_x,
      y: min_y,
      width: max_x - min_x,
      height: max_y - min_y
    }

    # SVG polygon points 文字列を事前生成
    polygon_points_str =
      points
      |> Enum.map(fn p -> "#{safe_int(p["x"])},#{safe_int(p["y"])}" end)
      |> Enum.join(" ")

    {polygon_points_str, bbox}
  end

  # 旧矩形データの場合（後方互換性）
  defp extract_preview_data(%{"x" => x, "y" => y, "width" => w, "height" => h}) do
    bbox = %{x: safe_int(x), y: safe_int(y), width: safe_int(w), height: safe_int(h)}
    {nil, bbox}
  end

  defp extract_preview_data(_), do: {nil, nil}

  # ポリゴン外の塗り色を bbox 外周のサンプル平均から決定する。
  # 失敗時は #ffffff にフォールバック。
  defp polygon_fill_color(image_path, %{"points" => points})
       when is_list(points) and length(points) >= 3 do
    case AlchemIiif.Ingestion.ImageProcessor.sample_polygon_border_color(image_path, points) do
      {:ok, hex} -> hex
      _ -> "#ffffff"
    end
  end

  defp polygon_fill_color(_image_path, _geo), do: "#ffffff"

  # ポリゴン外周のフェザー半径を bbox サイズから決める。
  # min(w,h) の 3.0% を基準に最低 7.5px。原寸座標系（user space）の値。
  defp polygon_feather_radius(%{width: w, height: h})
       when is_number(w) and is_number(h) and w > 0 and h > 0 do
    Float.round(max(7.5, min(w, h) * 0.03), 2)
  end

  defp polygon_feather_radius(_), do: 7.5

  # 安全な整数変換
  defp safe_int(val) when is_integer(val), do: val
  defp safe_int(val) when is_float(val), do: round(val)

  defp safe_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp safe_int(_), do: 0

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

        <%!-- 差し戻しアラート --%>
        <%= if @is_rejected do %>
          <div class="rejection-alert">
            <div class="rejection-alert-header">
              <span class="rejection-alert-icon">⚠️</span>
              <span class="rejection-alert-title">この図版（またはプロジェクト）は差し戻されました</span>
            </div>
            <%= if @pdf_source.return_message do %>
              <div class="rejection-reason-box">
                <span class="rejection-reason-label">管理者からの全体コメント:</span>
                <span class="rejection-reason-text">{@pdf_source.return_message}</span>
              </div>
            <% end %>
            <%= if @extracted_image.review_comment do %>
              <div class="rejection-reason-box">
                <span class="rejection-reason-label">この画像へのコメント:</span>
                <span class="rejection-reason-text">{@extracted_image.review_comment}</span>
              </div>
            <% end %>
            <p class="rejection-alert-hint">修正を行い「再提出する」ボタンを押してください。</p>
          </div>
        <% end %>

        <%!-- Auto-Save ステータス --%>
        <.auto_save_indicator state={@save_state} />

        <%!-- クロッププレビュー画像 --%>
        <div class={if @has_crop, do: "label-crop-preview", else: "label-preview"}>
          <%= if @has_crop && @bbox do %>
            <svg
              viewBox={"#{@bbox.x} #{@bbox.y} #{@bbox.width} #{@bbox.height}"}
              class="label-crop-svg"
              preserveAspectRatio="xMidYMid meet"
            >
              <%!-- 周囲色: mask 外の透過領域を画像の外周色で塗りつぶし --%>
              <rect
                x={@bbox.x}
                y={@bbox.y}
                width={@bbox.width}
                height={@bbox.height}
                fill={@polygon_fill}
              />
              <%= if @polygon_points do %>
                <%!-- ポリゴンを mask + feGaussianBlur でフェザー化し境界を自然に --%>
                <defs>
                  <filter id="polygon-feather" x="-20%" y="-20%" width="140%" height="140%">
                    <feGaussianBlur stdDeviation={polygon_feather_radius(@bbox)} />
                  </filter>
                  <mask
                    id="polygon-mask"
                    maskUnits="userSpaceOnUse"
                    x={@bbox.x}
                    y={@bbox.y}
                    width={@bbox.width}
                    height={@bbox.height}
                  >
                    <rect
                      x={@bbox.x}
                      y={@bbox.y}
                      width={@bbox.width}
                      height={@bbox.height}
                      fill="black"
                    />
                    <polygon points={@polygon_points} fill="white" filter="url(#polygon-feather)" />
                  </mask>
                </defs>
                <image
                  href={@image_url}
                  width={@orig_w}
                  height={@orig_h}
                  mask="url(#polygon-mask)"
                />
              <% else %>
                <%!-- 旧矩形データ: クリップなし --%>
                <image
                  href={@image_url}
                  width={@orig_w}
                  height={@orig_h}
                />
              <% end %>
            </svg>
          <% else %>
            <img src={@image_url} alt="選択した図版" class="label-preview-image" />
          <% end %>
        </div>

        <%!-- メタデータ入力フォーム（phx-change でリアルタイムバリデーション） --%>
        <form phx-change="validate_metadata" class="metadata-form">
          <div class="form-group">
            <label for="caption-input" class="form-label">📝 キャプション（図の説明）</label>
            <input
              type="text"
              id="caption-input"
              class={["form-input form-input-large", @validation_errors[:caption] && "input-error"]}
              value={@caption}
              phx-blur="blur_save_field"
              phx-value-field="caption"
              placeholder="例: 第3図 土器出土状況"
              name="caption"
              maxlength="1000"
            />
            <%!-- キャプションエラー --%>
            <%= if @validation_errors[:caption] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:caption]}</p>
            <% end %>
          </div>

          <div class="form-group">
            <label for="label-input" class="form-label">🏷️ ラベル（短い識別名）</label>
            <input
              type="text"
              id="label-input"
              class={[
                "form-input form-input-large",
                (@duplicate_record || @validation_errors[:label]) && "input-error"
              ]}
              value={@label}
              phx-blur="blur_save_field"
              phx-value-field="label"
              placeholder="例: fig-1-1"
              name="label"
              maxlength="100"
            />

            <%!-- ラベル形式エラー --%>
            <%= if @validation_errors[:label] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:label]}</p>
            <% end %>

            <%!-- 重複検出警告 --%>
            <%= if @duplicate_record do %>
              <div class="duplicate-warning">
                <p class="duplicate-error-text">
                  ⚠️ この遺跡でそのラベルは既に登録されています
                </p>
                <div class="duplicate-card">
                  <div class="duplicate-card-info">
                    <span class="duplicate-card-label">重複先:</span>
                    <span class="duplicate-card-id">
                      ID: #{@duplicate_record.id}
                    </span>
                    <span class="duplicate-card-caption">
                      {@duplicate_record.caption || "（キャプションなし）"}
                    </span>
                  </div>
                  <button
                    type="button"
                    class="btn-merge"
                    phx-click="merge_existing"
                    aria-label="既存レコードを編集"
                  >
                    📝 既存レコードを更新
                  </button>
                </div>
              </div>
            <% end %>
          </div>

          <div class="form-group">
            <label for="site-input" class="form-label">📍 遺跡名（任意）</label>
            <input
              type="text"
              id="site-input"
              class={["form-input form-input-large", @validation_errors[:site] && "input-error"]}
              value={@site}
              phx-blur="blur_save_field"
              phx-value-field="site"
              placeholder="例: 新潟市中野遺跡"
              name="site"
            />
            <%!-- 遺跡名エラー --%>
            <%= if @validation_errors[:site] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:site]}</p>
            <% end %>
          </div>

          <div class="form-group">
            <label for="period-input" class="form-label">⏳ 時代（任意）</label>
            <input
              type="text"
              id="period-input"
              class={["form-input form-input-large", @validation_errors[:period] && "input-error"]}
              value={@period}
              phx-blur="blur_save_field"
              phx-value-field="period"
              placeholder="例: 縄文時代"
              name="period"
            />
            <%!-- 時代エラー --%>
            <%= if @validation_errors[:period] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:period]}</p>
            <% end %>
          </div>

          <div class="form-group">
            <label for="artifact-type-input" class="form-label">🏺 遺物種別（任意）</label>
            <input
              type="text"
              id="artifact-type-input"
              class={[
                "form-input form-input-large",
                @validation_errors[:artifact_type] && "input-error"
              ]}
              value={@artifact_type}
              phx-blur="blur_save_field"
              phx-value-field="artifact_type"
              placeholder="例: 土器"
              name="artifact_type"
            />
            <%!-- 遺物種別エラー --%>
            <%= if @validation_errors[:artifact_type] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:artifact_type]}</p>
            <% end %>
          </div>

          <div class="form-group">
            <label for="material-input" class="form-label">🧱 素材（任意）</label>
            <input
              type="text"
              id="material-input"
              class={["form-input form-input-large", @validation_errors[:material] && "input-error"]}
              value={@material}
              phx-blur="blur_save_field"
              phx-value-field="material"
              placeholder="土師器、黒曜石、鉄製品 など"
              name="material"
              maxlength="100"
            />
            <%= if @validation_errors[:material] do %>
              <p class="field-error-text">⚠️ {@validation_errors[:material]}</p>
            <% end %>
          </div>
        </form>

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

        <div class="action-bar-split">
          <.link
            navigate={~p"/lab/crop/#{@extracted_image.pdf_source_id}/#{@extracted_image.page_number}"}
            class="btn-secondary btn-large"
          >
            ← 戻る
          </.link>

          <div class="action-buttons">
            <%= if @is_rejected do %>
              <%!-- 再提出モード: 1つのボタンのみ --%>
              <button
                type="button"
                class="btn-resubmit btn-large"
                phx-click="save"
                phx-value-action="finish"
                aria-label="再提出する"
              >
                <span class="btn-icon">🔄</span>
                <span>再提出する</span>
              </button>
            <% else %>
              <button
                type="button"
                class="btn-save-continue"
                phx-click="save"
                phx-value-action="continue"
                aria-label="保存して次の図版へ"
              >
                <span class="btn-icon">🔄</span>
                <span>保存して次の図版へ</span>
              </button>

              <button
                type="button"
                class="btn-save-finish"
                phx-click="save"
                phx-value-action="finish"
                aria-label="保存して終了"
              >
                <span class="btn-icon">✅</span>
                <span>保存して終了</span>
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
