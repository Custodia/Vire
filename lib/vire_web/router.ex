defmodule VireWeb.Router do
  use VireWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
  end

  scope "/api", VireWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
    match :*, "/*path", NotFoundController, :show
  end

  scope "/", VireWeb do
    match :*, "/assets/*path", DashboardController, :not_found
    get "/*path", DashboardController, :index
  end
end
