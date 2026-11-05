defmodule VireWeb.ChannelCase do
  use ExUnit.CaseTemplate

  alias Phoenix.Socket.Transport

  using do
    quote do
      @endpoint VireWeb.Endpoint

      import Phoenix.ChannelTest
      import Vire.AccountsFixtures
      import VireWeb.ChannelCase, only: [connect_info: 2]
    end
  end

  @doc """
  What the WebSocket transport hands the socket's `connect/3` for a request
  carrying `conn`'s cookies and `csrf_token` as its `_csrf_token` parameter,
  through the transport's own session and CSRF checks.
  """
  def connect_info(conn, csrf_token) do
    [{"/socket", VireWeb.UserSocket, opts}] = VireWeb.Endpoint.__sockets__()

    config =
      Transport.load_config(opts[:websocket], Phoenix.Transports.WebSocket)

    request = %{Phoenix.ConnTest.recycle(conn) | params: %{"_csrf_token" => csrf_token}}

    request
    |> Transport.connect_info(VireWeb.Endpoint, config[:connect_info])
    |> Map.new()
  end

  setup tags do
    Vire.DataCase.setup_sandbox(tags)
    :ok
  end
end
