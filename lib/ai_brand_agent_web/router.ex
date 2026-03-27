defmodule AiBrandAgentWeb.Router do
  use AiBrandAgentWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug AiBrandAgentWeb.Plugs.OptionalAuth
    plug :put_root_layout, html: {AiBrandAgentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug AiBrandAgentWeb.Plugs.Auth
  end

  # ── Public routes ───────────────────────────────────────────────────

  scope "/", AiBrandAgentWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # ── Auth routes (no auth plug — these handle login/logout) ─────────

  scope "/auth", AiBrandAgentWeb do
    pipe_through :browser

    get "/auth0", AuthController, :login
    get "/auth0/callback", AuthController, :callback
    get "/logout", AuthController, :logout
  end

  # Linking LinkedIn/Facebook must run while logged in so we can verify the
  # Auth0 profile matches the existing user (avoid switching to facebook|… user).
  scope "/auth", AiBrandAgentWeb do
    pipe_through [:browser, :require_auth]

    get "/connect/:platform", AuthController, :connect

    get "/connected-accounts/start", ConnectedAccountsController, :start
    get "/connected-accounts/callback", ConnectedAccountsController, :callback
  end

  # ── Authenticated routes ────────────────────────────────────────────

  scope "/", AiBrandAgentWeb do
    pipe_through [:browser, :require_auth]

    live "/dashboard", DashboardLive
    live "/niches", NichesLive
    live "/brand", BrandLive
    live "/posts", PostsLive
    live "/posts/new", PostComposeLive
    live "/posts/:id", PostDetailLive
    live "/connections", ConnectionsLive
    live "/agent", AgentSettingsLive
  end

  # ── Dev routes ──────────────────────────────────────────────────────

  if Application.compile_env(:ai_brand_agent, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AiBrandAgentWeb.Telemetry
    end
  end
end
