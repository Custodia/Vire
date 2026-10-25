defmodule VireWeb.SessionControllerTest do
  use VireWeb.ConnCase, async: true

  @invalid %{"errors" => %{"detail" => "Invalid email or password"}}

  setup do
    %{user: user_fixture(email: "ada@example.com", name: "Ada")}
  end

  describe "POST /api/session" do
    test "signs in with the right password and answers with the user", %{conn: conn, user: user} do
      conn =
        post_json(conn, ~p"/api/session", %{email: "ADA@example.com", password: valid_password()})

      assert json_response(conn, 200) == %{
               "id" => user.id,
               "email" => "ada@example.com",
               "name" => "Ada"
             }

      assert get_session(conn, :user_id) == user.id
    end

    test "sets an HttpOnly, SameSite Lax, encrypted session cookie", %{conn: conn, user: user} do
      conn = post_json(conn, ~p"/api/session", %{email: user.email, password: valid_password()})

      [header] = get_resp_header(conn, "set-cookie")
      assert header =~ ~r/^_vire_session=[^;]+; path=\/; HttpOnly; SameSite=Lax$/

      segments =
        conn.resp_cookies["_vire_session"].value
        |> String.split(".")
        |> Enum.flat_map(&List.wrap(decode_segment(&1)))

      assert length(segments) > 1
      refute Enum.any?(segments, &String.contains?(&1, user.id))
    end

    test "starts a fresh session that keeps nothing from the one before", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> init_test_session(planted: "x")
        |> post_json(~p"/api/session", %{email: user.email, password: valid_password()})

      assert get_session(conn, :user_id) == user.id
      assert get_session(conn, :planted) == nil
    end

    test "refuses a urlencoded cross-site form post with 415", %{conn: conn, user: user} do
      conn =
        conn
        |> put_req_header("origin", "https://evil.example")
        |> put_req_header("accept", "text/html,application/xhtml+xml,*/*;q=0.8")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(
          ~p"/api/session",
          URI.encode_query(%{email: user.email, password: valid_password()})
        )

      assert json_response(conn, 415) == %{"errors" => %{"detail" => "Unsupported Media Type"}}
      assert get_session(conn, :user_id) == nil
      assert get_resp_header(conn, "set-cookie") == []
    end

    test "answers a wrong password with 401", %{conn: conn, user: user} do
      conn = post_json(conn, ~p"/api/session", %{email: user.email, password: "not the password"})

      assert json_response(conn, 401) == @invalid
      assert get_session(conn, :user_id) == nil
    end

    test "answers an unknown email with the same 401", %{conn: conn} do
      conn =
        post_json(conn, ~p"/api/session", %{
          email: "nobody@example.com",
          password: valid_password()
        })

      assert json_response(conn, 401) == @invalid
      assert get_session(conn, :user_id) == nil
    end

    test "answers a body without an email and a password with 400", %{conn: conn} do
      conn = post_json(conn, ~p"/api/session", %{email: ["ada@example.com"]})

      assert json_response(conn, 400) == %{"errors" => %{"detail" => "Bad Request"}}
    end
  end

  describe "DELETE /api/session" do
    test "signs out and expires the cookie", %{conn: conn, user: user} do
      conn =
        conn
        |> post_json(~p"/api/session", %{email: user.email, password: valid_password()})
        |> recycle()
        |> delete(~p"/api/session")

      assert response(conn, 204) == ""
      assert [header] = get_resp_header(conn, "set-cookie")
      assert header =~ "_vire_session=;"
      assert header =~ "max-age=0"
    end
  end

  test "production marks the session cookie Secure" do
    config = Config.Reader.read!("config/prod.exs", env: :prod)

    assert config[:vire][:secure_session_cookie] == true
  end

  defp post_json(conn, path, params) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(params))
  end

  defp decode_segment(segment) do
    case Base.url_decode64(segment, padding: false) do
      {:ok, bytes} -> bytes
      :error -> nil
    end
  end
end
