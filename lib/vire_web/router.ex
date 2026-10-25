defmodule VireWeb.Router do
  use VireWeb, :router

  import VireWeb.CSRF, only: [require_csrf_token: 2]

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :require_csrf_token
  end

  scope "/api", VireWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/csrf", CSRFController, :show
    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
    match :*, "/*path", NotFoundController, :show
  end

  scope "/", VireWeb do
    match :*, "/assets/*path", DashboardController, :not_found
    get "/*path", DashboardController, :index
  end
end
