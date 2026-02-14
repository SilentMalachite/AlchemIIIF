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

  alias AlchemIiif.Ingestion.ImageProcessor
  alias AlchemIiif.Search

  @impl true
  def mount(_params, _session, socket) do
    # 利用可能なフィルターオプションを取得
    filter_options = Search.list_filter_options()

    # 公開済み画像のみ表示
    results = Search.search_published_images()
    match_count = Search.count_published_results()
    dims_map = build_dims_map(results)

    {:ok,
     socket
     |> assign(:page_title, "ギャラリー")
     |> assign(:query, "")
     |> assign(:filters, %{})
     |> assign(:filter_options, filter_options)
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:dims_map, dims_map)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    results = Search.search_published_images(query, socket.assigns.filters)
    match_count = Search.count_published_results(query, socket.assigns.filters)
    dims_map = build_dims_map(results)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:dims_map, dims_map)}
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
    match_count = Search.count_published_results(socket.assigns.query, updated_filters)
    dims_map = build_dims_map(results)

    {:noreply,
     socket
     |> assign(:filters, updated_filters)
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:dims_map, dims_map)}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    results = Search.search_published_images(socket.assigns.query, %{})
    match_count = Search.count_published_results(socket.assigns.query, %{})
    dims_map = build_dims_map(results)

    {:noreply,
     socket
     |> assign(:filters, %{})
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:dims_map, dims_map)}
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
        {result_text(@match_count)}
      </div>

      <%= if @match_count == 0 do %>
        <div class="no-results-container">
          <div class="no-results-card">
            <div class="no-results-icon-box">
              <.icon name="hero-magnifying-glass" class="w-16 h-16 text-[#A0AEC0] opacity-40" />
            </div>
            <h2 class="no-results-title">条件に一致する図版はありませんでした。</h2>
            <p class="section-description">
              <%= if @query != "" || @filters != %{} do %>
                検索キーワードやフィルターを変更してみてください。
              <% else %>
                まだ公開済みの図版がありません。
              <% end %>
            </p>
            <%= if @query != "" || @filters != %{} do %>
              <button
                type="button"
                class="btn-reset-filters"
                phx-click="clear_filters"
              >
                <.icon name="hero-arrow-path" class="w-5 h-5" /> 検索条件をリセット
              </button>
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="results-grid columns-1 sm:columns-2 md:columns-3 lg:columns-4 gap-4 space-y-4">
          <%= for image <- @results do %>
            <div class="result-card break-inside-avoid mb-4">
              <a href={manifest_url(image)} class="result-card-link" target="_blank">
                <%= if image.geometry do %>
                  <% geo = image.geometry %>
                  <% {orig_w, orig_h} = Map.get(@dims_map, image.id, {0, 0}) %>
                  <div class="relative w-full bg-[#0F1923] flex items-center justify-center rounded-t-lg overflow-hidden">
                    <svg
                      viewBox={"#{geo["x"]} #{geo["y"]} #{geo["width"]} #{geo["height"]}"}
                      class="w-full h-auto"
                      preserveAspectRatio="xMidYMid meet"
                    >
                      <image
                        href={image_thumbnail_url(image)}
                        width={orig_w}
                        height={orig_h}
                      />
                    </svg>
                  </div>
                <% else %>
                  <img
                    src={image_thumbnail_url(image)}
                    alt={image.caption || "図版"}
                    class="result-card-image"
                    loading="lazy"
                  />
                <% end %>
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
              <%!-- ダウンロードボタン --%>
              <a
                href={~p"/download/#{image}"}
                class="download-btn"
                title="高解像度画像をダウンロード"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="download-icon"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                  />
                </svg>
                ダウンロード
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

  # 画像寸法マップの構築（SVG viewBox クロップ表示用）
  defp build_dims_map(images) do
    Map.new(images, fn image ->
      dims = read_source_dimensions(image.image_path)
      {image.id, dims}
    end)
  end

  # 元画像の寸法を Vix で読み取る（ヘッダーのみ遅延読み込みなので軽量）
  defp read_source_dimensions(image_path) do
    case ImageProcessor.get_image_dimensions(image_path) do
      {:ok, %{width: w, height: h}} -> {w, h}
      _error -> {0, 0}
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
