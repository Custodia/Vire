defmodule VireWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint VireWeb.Endpoint

      use VireWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
    end
  end

  setup tags do
    Vire.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
