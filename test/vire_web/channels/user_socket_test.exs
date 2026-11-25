defmodule VireWeb.UserSocketTest do
  use VireWeb.ChannelCase, async: true

  import Phoenix.ConnTest, only: [build_conn: 0, dispatch: 4, json_response: 2, recycle: 1]
  import VireWeb.ConnCase, only: [sign_in: 2]

  alias Vire.Repo
  alias VireWeb.UserSocket

  setup do
    user = user_fixture()
    {conn, token} = build_conn() |> sign_in(user) |> with_csrf_token()
    %{user: user, conn: conn, token: token}
  end

  test "connects a signed-in session carrying its CSRF token", context do
    assert {:ok, socket} = connect_with(context.conn, context.token)

    assert socket.assigns.scope.user.id == context.user.id
    assert "user_sockets:" <> _ = UserSocket.id(socket)
  end

  test "refuses a session without its CSRF token", context do
    {_other, other_token} = with_csrf_token(build_conn())

    assert connect_with(context.conn, nil) == :error
    assert connect_with(context.conn, other_token) == :error
  end

  test "refuses a session without a user" do
    {conn, token} = with_csrf_token(build_conn())

    assert connect_with(conn, token) == :error
  end

  test "refuses the session of a deleted user", context do
    Repo.delete!(context.user)

    assert connect_with(context.conn, context.token) == :error
  end

  # A socket connected in the test process subscribes it to the socket's id.
  test "signing out disconnects that session's sockets only", context do
    {:ok, socket} = connect_with(context.conn, context.token)
    {other, other_token} = build_conn() |> sign_in(context.user) |> with_csrf_token()
    {:ok, other_socket} = connect_with(other, other_token)
    socket_id = UserSocket.id(socket)
    refute UserSocket.id(other_socket) == socket_id

    context.conn |> recycle() |> dispatch(@endpoint, :delete, "/api/session")

    assert_receive %Phoenix.Socket.Broadcast{topic: ^socket_id, event: "disconnect"}
    refute_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
  end

  defp connect_with(conn, token),
    do: connect(UserSocket, %{}, connect_info: connect_info(conn, token))

  defp with_csrf_token(conn) do
    conn = conn |> recycle() |> dispatch(@endpoint, :get, "/api/csrf")
    {conn, json_response(conn, 200)["token"]}
  end
end
