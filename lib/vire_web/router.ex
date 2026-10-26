defmodule VireWeb.Router do
  use VireWeb, :router

  import VireWeb.Auth, only: [fetch_current_scope: 2, require_authenticated: 2]
  import VireWeb.McpAuth, only: [check_origin: 2, require_mcp_token: 2]

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_current_scope
  end

  pipeline :authenticated do
    plug :require_authenticated
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {VireWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_content_security_policy
    plug :fetch_current_scope
  end

  # Browser-based clients fetch these documents and call these endpoints from
  # their own origin. None of them reads a cookie.
  pipeline :oauth do
    plug :allow_any_origin
  end

  pipeline :mcp do
    plug :check_origin
    plug :require_mcp_token
  end

  scope "/", VireWeb do
    pipe_through :mcp

    post "/mcp", McpController, :create
  end

  scope "/", VireWeb do
    get "/mcp", McpController, :method_not_allowed
    delete "/mcp", McpController, :method_not_allowed
    get "/files/:id", FileController, :show
  end

  scope "/api", VireWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end

  scope "/api", VireWeb do
    pipe_through [:api, :authenticated]

    get "/me", MeController, :show
    post "/uploads", UploadController, :create
    get "/uploads/:id", UploadController, :show
  end

  scope "/api", VireWeb do
    pipe_through :api

    match :*, "/*path", NotFoundController, :show
  end

  scope "/", VireWeb do
    pipe_through :oauth

    get "/.well-known/oauth-protected-resource", OAuthMetadataController, :protected_resource
    get "/.well-known/oauth-protected-resource/mcp", OAuthMetadataController, :protected_resource
    get "/.well-known/oauth-authorization-server", OAuthMetadataController, :authorization_server
    post "/oauth/register", OAuthRegistrationController, :create
    post "/oauth/token", OAuthTokenController, :create

    options "/.well-known/*path", CorsController, :preflight
    options "/oauth/register", CorsController, :preflight
    options "/oauth/token", CorsController, :preflight
    match :*, "/.well-known/*path", NotFoundController, :show
  end

  scope "/oauth", VireWeb do
    pipe_through :browser

    get "/authorize", OAuthAuthorizationController, :new
    post "/authorize", OAuthAuthorizationController, :create
    post "/sign_in", OAuthAuthorizationController, :sign_in
  end

  scope "/", VireWeb do
    match :*, "/assets/*path", DashboardController, :not_found
    get "/*path", DashboardController, :index
  end

  defp put_content_security_policy(conn, _opts) do
    put_secure_browser_headers(conn, %{
      "content-security-policy" =>
        "default-src 'none'; style-src #{VireWeb.Layouts.style_source()}; img-src 'self'; " <>
          "frame-ancestors 'none'; base-uri 'none'"
    })
  end

  defp allow_any_origin(conn, _opts),
    do: put_resp_header(conn, "access-control-allow-origin", "*")
end
