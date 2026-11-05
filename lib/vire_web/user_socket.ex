defmodule VireWeb.UserSocket do
  @moduledoc """
  The dashboard's WebSocket. It connects with the session cookie and the
  session's CSRF token, for a signed-in user only, and takes the session's
  `live_socket_id` as its id, so that signing out closes that session's
  sockets.
  """

  use Phoenix.Socket

  alias Vire.Accounts
  alias Vire.Accounts.Scope

  channel "user:*", VireWeb.UserChannel

  @impl true
  def connect(_params, socket, %{session: %{"user_id" => user_id} = session}) do
    case Accounts.get_user(user_id) do
      nil ->
        :error

      user ->
        {:ok,
         assign(socket, scope: Scope.for_user(user), live_socket_id: session["live_socket_id"])}
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: socket.assigns.live_socket_id
end
