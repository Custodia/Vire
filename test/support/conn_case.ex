defmodule VireWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint VireWeb.Endpoint

      use VireWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Vire.AccountsFixtures
      import VireWeb.ConnCase, only: [sign_in: 2]
    end
  end

  @doc "Signs `user` in through the API and carries the session cookie forward."
  def sign_in(conn, user) do
    body =
      Jason.encode!(%{email: user.email, password: Vire.AccountsFixtures.valid_password()})

    conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.dispatch(VireWeb.Endpoint, :post, "/api/session", body)
    |> Phoenix.ConnTest.recycle()
  end

  setup tags do
    Vire.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
