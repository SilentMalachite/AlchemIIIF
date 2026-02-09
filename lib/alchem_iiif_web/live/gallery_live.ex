defmodule AlchemIiifWeb.GalleryLive do
  @moduledoc """
  公開ギャラリー (Museum) LiveView。
  status == 'published' の画像のみを表示する読み取り専用ビューです。
  編集ツールや Nudge ボタンは配置しません。

  認知アクセシビリティ対応:
  - 大きなフィルターチップス（最小60x60px）
  - サムネイルグリッドで結果表示（テキスト密度を低減）
  - search-as-you-type（300ms デバウンス）
  """
  use AlchemIiifWeb, :live_view

  alias AlchemIiif.Search

  @impl true
  def mount(_params, _session, socket) do
    # 利用可能なフィルターオプションを取得
    filter_options = Search.list_filter_options()

    # 公開済み画像のみ表示
    results = Search.search_published_images()
    result_count = length(results)

    {:ok,
     socket
     |> assign(:page_title, "ギャラリー")
     |> assign(:query, "")
     |> assign(:filters, %{})
     |> assign(:filter_options, filter_options)
     |> assign(:results, results)
     |> assign(:result_count, result_count)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    results = Search.search_published_images(query, socket.assigns.filters)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:results, results)
     |> assign(:result_count, length(results))}
  end

  @impl true
  def handle_event("toggle_filter", %{"type" => type, "value" => value}, socket) do
    filters = socket.assigns.filters

    # 同じフィルターを再度クリックした場合はクリア
    updated_filters =
      if filters[type] == value do
        Map.delete(filters, type)
      else
        Map.put(filters, type, value)
      end

    results = Search.search_published_images(socket.assigns.query, updated_filters)

    {:noreply,
     socket
     |> assign(:filters, updated_filters)
     |> assign(:results, results)
     |> assign(:result_count, length(results))}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    results = Search.search_published_images(socket.assigns.query, %{})

    {:noreply,
     socket
     |> assign(:filters, %{})
     |> assign(:results, results)
     |> assign(:result_count, length(results))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="gallery-container">
      <div class="gallery-header">
        <h1 class="section-title">🏛️ ギャラリー</h1>
        <p class="section-description">
          公開済みの図版コレクションです。キーワードやフィルターで検索できます。
        </p>
      </div>

      <%!-- 検索バー --%>
      <div class="search-bar">
        <span class="search-icon">🔍</span>
        <input
          type="search"
          id="gallery-search-input"
          class="search-input"
          placeholder="キャプション、ラベル、遺跡名で検索..."
          value={@query}
          phx-keyup="search"
          phx-value-query={@query}
          phx-debounce="300"
          name="query"
          autocomplete="off"
        />
      </div>

      <%!-- フィルターチップス --%>
      <div class="filter-section">
        <%= if has_any_filters?(@filter_options) do %>
          <%!-- 遺跡名フィルター --%>
          <%= if @filter_options.sites != [] do %>
            <div class="filter-group">
              <span class="filter-group-label">📍 遺跡名</span>
              <div class="filter-chips">
                <%= for site <- @filter_options.sites do %>
                  <button
                    type="button"
                    class={"filter-chip #{if @filters["site"] == site, do: "active", else: ""}"}
                    phx-click="toggle_filter"
                    phx-value-type="site"
                    phx-value-value={site}
                    aria-pressed={@filters["site"] == site}
                  >
                    {site}
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- 時代フィルター --%>
          <%= if @filter_options.periods != [] do %>
            <div class="filter-group">
              <span class="filter-group-label">⏳ 時代</span>
              <div class="filter-chips">
                <%= for period <- @filter_options.periods do %>
                  <button
                    type="button"
                    class={"filter-chip #{if @filters["period"] == period, do: "active", else: ""}"}
                    phx-click="toggle_filter"
                    phx-value-type="period"
                    phx-value-value={period}
                    aria-pressed={@filters["period"] == period}
                  >
                    {period}
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- 遺物種別フィルター --%>
          <%= if @filter_options.artifact_types != [] do %>
            <div class="filter-group">
              <span class="filter-group-label">🏺 遺物種別</span>
              <div class="filter-chips">
                <%= for artifact_type <- @filter_options.artifact_types do %>
                  <button
                    type="button"
                    class={"filter-chip #{if @filters["artifact_type"] == artifact_type, do: "active", else: ""}"}
                    phx-click="toggle_filter"
                    phx-value-type="artifact_type"
                    phx-value-value={artifact_type}
                    aria-pressed={@filters["artifact_type"] == artifact_type}
                  >
                    {artifact_type}
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- フィルタークリア --%>
          <%= if @filters != %{} do %>
            <button
              type="button"
              class="btn-secondary btn-large"
              phx-click="clear_filters"
              style="margin-top: 1rem;"
            >
              ✕ フィルターをクリア
            </button>
          <% end %>
        <% end %>
      </div>

      <%!-- 検索結果 --%>
      <div class="results-count">
        {result_text(@result_count)}
      </div>

      <%= if @results == [] do %>
        <div class="no-results">
          <span class="no-results-icon">📭</span>
          <p class="section-description">
            <%= if @query != "" || @filters != %{} do %>
              条件に一致する図版が見つかりませんでした。<br /> 検索キーワードやフィルターを変更してみてください。
            <% else %>
              まだ公開済みの図版がありません。
            <% end %>
          </p>
        </div>
      <% else %>
        <div class="results-grid">
          <%= for image <- @results do %>
            <div class="result-card">
              <a href={manifest_url(image)} class="result-card-link" target="_blank">
                <img
                  src={image_thumbnail_url(image)}
                  alt={image.caption || "図版"}
                  class="result-card-image"
                  loading="lazy"
                />
                <div class="result-card-body">
                  <h3 class="result-card-title">{image.label || "名称未設定"}</h3>
                  <%= if image.caption do %>
                    <p class="result-card-caption">{image.caption}</p>
                  <% end %>
                  <div class="result-card-meta">
                    <%= if image.site do %>
                      <span class="meta-tag">📍 {image.site}</span>
                    <% end %>
                    <%= if image.period do %>
                      <span class="meta-tag">⏳ {image.period}</span>
                    <% end %>
                    <%= if image.artifact_type do %>
                      <span class="meta-tag">🏺 {image.artifact_type}</span>
                    <% end %>
                  </div>
                </div>
              </a>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- プライベート関数 ---

  # フィルターオプションが存在するかチェック
  defp has_any_filters?(filter_options) do
    filter_options.sites != [] ||
      filter_options.periods != [] ||
      filter_options.artifact_types != []
  end

  # 結果件数のテキスト
  defp result_text(0), do: "結果なし"
  defp result_text(count), do: "#{count} 件の図版が見つかりました"

  # Manifest URL の生成
  defp manifest_url(image) do
    case image.iiif_manifest do
      nil -> "#"
      manifest -> "/iiif/manifest/#{manifest.identifier}"
    end
  end

  # サムネイル URL の生成
  defp image_thumbnail_url(image) do
    case image.iiif_manifest do
      nil ->
        # PTIF なし：元画像を使用
        image.image_path
        |> String.replace_leading("priv/static/", "/")

      manifest ->
        # IIIF Image API でサムネイルを取得
        "/iiif/image/#{manifest.identifier}/full/300,/0/default.jpg"
    end
  end
end
