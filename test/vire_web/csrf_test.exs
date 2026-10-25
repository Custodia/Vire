defmodule VireWeb.CSRFTest do
  use VireWeb.ConnCase, async: true

  import Vire.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: protected(conn), user: user}
  end

  test "GET /api/csrf answers a token for the session", %{conn: conn} do
    conn = get(conn, ~p"/api/csrf")

    assert %{"token" => token} = json_response(conn, 200)
    assert is_binary(token)
    assert get_session(conn, "_csrf_token")
  end

  test "an unsafe request carrying the session's token goes through", %{conn: conn, user: user} do
    {conn, token} = fetch_token(conn)

    conn = conn |> put_req_header("x-csrf-token", token) |> sign_in_request(user)

    assert json_response(conn, 200)["id"] == user.id
  end

  test "an unsafe request without a token answers 403", %{conn: conn, user: user} do
    {conn, _token} = fetch_token(conn)

    conn = sign_in_request(conn, user)

    assert json_response(conn, 403) == %{
             "reason" => "invalid_csrf_token",
             "errors" => %{"detail" => "The request does not carry the session's CSRF token"}
           }

    assert get_session(conn, :user_id) == nil
  end

  test "an unsafe request with another session's token answers 403", %{conn: conn, user: user} do
    {_other, token} = fetch_token(protected(build_conn()))
    {conn, _token} = fetch_token(conn)

    conn = conn |> put_req_header("x-csrf-token", token) |> sign_in_request(user)

    assert json_response(conn, 403)["reason"] == "invalid_csrf_token"
  end

  test "a GET needs no token", %{conn: conn} do
    assert json_response(get(conn, ~p"/api/health"), 200)
  end

  test "signing in ends the token the session held before", %{conn: conn, user: user} do
    {conn, token} = fetch_token(conn)

    conn =
      conn
      |> put_req_header("x-csrf-token", token)
      |> sign_in_request(user)
      |> recycle()
      |> protected()
      |> put_req_header("x-csrf-token", token)
      |> delete(~p"/api/session")

    assert json_response(conn, 403)["reason"] == "invalid_csrf_token"

    {conn, token} = fetch_token(conn)
    conn = conn |> put_req_header("x-csrf-token", token) |> delete(~p"/api/session")

    assert response(conn, 204)
  end

  # Phoenix.ConnTest skips CSRF protection on every connection it builds.
  defp protected(conn), do: put_private(conn, :plug_skip_csrf_protection, false)

  defp fetch_token(conn) do
    conn = get(conn, ~p"/api/csrf")
    %{"token" => token} = json_response(conn, 200)
    {conn |> recycle() |> protected(), token}
  end

  defp sign_in_request(conn, user) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/session", Jason.encode!(%{email: user.email, password: valid_password()}))
  end
end
