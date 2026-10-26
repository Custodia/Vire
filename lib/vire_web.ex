defmodule VireWeb do
  @moduledoc """
  Entry point for routers, controllers and templates: `use VireWeb, :controller`.
  """

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn
    end
  end

  def html_controller do
    quote do
      use Phoenix.Controller, formats: [:html]

      import Plug.Conn
    end
  end

  def html do
    quote do
      import Phoenix.HTML
      import Phoenix.Template, only: [embed_templates: 1]
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: VireWeb.Endpoint,
        router: VireWeb.Router
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
