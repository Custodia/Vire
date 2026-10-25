defmodule VireWeb.Router do
  use VireWeb, :router

  import VireWeb.Auth, only: [fetch_current_scope: 2, require_authenticated: 2]

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_current_scope
  end

  pipeline :authenticated do
    plug :require_authenticated
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
  end

  scope "/api", VireWeb do
    pipe_through :api

    match :*, "/*path", NotFoundController, :show
  end

  scope "/", VireWeb do
    match :*, "/assets/*path", DashboardController, :not_found
    get "/*path", DashboardController, :index
  end
end
