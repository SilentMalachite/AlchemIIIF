defmodule AlchemIiifWeb.Router do
  use AlchemIiifWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AlchemIiifWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AlchemIiifWeb do
    pipe_through :browser

    get "/", PageController, :home

    # 公開ギャラリー (Museum) — 読み取り専用、published のみ
    live "/gallery", GalleryLive, :index

    # Lab 名前空間 (Worker Space)
    live "/lab", InspectorLive.Upload, :index
    live "/lab/browse/:pdf_source_id", InspectorLive.Browse, :browse
    live "/lab/crop/:image_id", InspectorLive.Crop, :crop
    live "/lab/finalize/:image_id", InspectorLive.Finalize, :finalize
    live "/lab/search", SearchLive, :index
    live "/lab/approval", ApprovalLive, :index
  end

  # IIIF API エンドポイント
  scope "/iiif", AlchemIiifWeb.IIIF do
    pipe_through :api

    # Image API v3.0
    get "/image/:identifier/info.json", ImageController, :info
    get "/image/:identifier/:region/:size/:rotation/:quality", ImageController, :show

    # Presentation API v3.0
    get "/manifest/:identifier", ManifestController, :show
  end

  # ヘルスチェック用 API
  scope "/api", AlchemIiifWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:alchem_iiif, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AlchemIiifWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
