defmodule VireWeb.MeControllerTest do
  use VireWeb.ConnCase, async: true

  alias Vire.Repo

  @unauthorized %{"errors" => %{"detail" => "Unauthorized"}}

  test "answers 401 without a session", %{conn: conn} do
    conn = get(conn, ~p"/api/me")

    assert json_response(conn, 401) == @unauthorized
  end

  test "answers with the signed-in user", %{conn: conn} do
    user = user_fixture(email: "ada@example.com", name: "Ada")

    conn = conn |> sign_in(user) |> get(~p"/api/me")

    assert json_response(conn, 200) == %{
             "id" => user.id,
             "email" => "ada@example.com",
             "name" => "Ada"
           }
  end

  test "answers 401 after sign-out", %{conn: conn} do
    conn =
      conn
      |> sign_in(user_fixture())
      |> delete(~p"/api/session")
      |> recycle()
      |> get(~p"/api/me")

    assert json_response(conn, 401) == @unauthorized
  end

  test "answers 401 once the signed-in user is gone", %{conn: conn} do
    user = user_fixture()
    conn = sign_in(conn, user)
    Repo.delete!(user)

    conn = get(conn, ~p"/api/me")

    assert json_response(conn, 401) == @unauthorized
  end

  test "leaves the health check and unknown paths public", %{conn: conn} do
    assert json_response(get(conn, ~p"/api/health"), 200)
    assert json_response(get(conn, "/api/missing"), 404)
  end
end
