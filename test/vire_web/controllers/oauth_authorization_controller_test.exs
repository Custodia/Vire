defmodule VireWeb.OAuthAuthorizationControllerTest do
  use VireWeb.ConnCase, async: true

  alias Vire.Mcp.Token
  alias Vire.Repo

  setup do
    client = register_client(%{"client_name" => "Claude"})
    {verifier, challenge} = pkce()

    %{
      user: user_fixture(),
      client: client,
      verifier: verifier,
      params: authorize_params(client, challenge)
    }
  end

  test "a fresh browser signs in, consents, gets a code and exchanges it for tokens", %{
    user: user,
    client: client,
    verifier: verifier,
    params: params
  } do
    sign_in_page = get(browser(), ~p"/oauth/authorize", params)
    html = html_response(sign_in_page, 200)
    assert html =~ "Sign in to Vire"
    assert html =~ "<strong>Claude</strong> is asking for access"
    assert html =~ ~s(action="/oauth/sign_in")

    signed_in =
      sign_in_page
      |> follow()
      |> post(
        ~p"/oauth/sign_in",
        Map.merge(params, %{
          "_csrf_token" => csrf_token(html),
          "email" => user.email,
          "password" => valid_password()
        })
      )

    assert "/oauth/authorize?" <> query = redirected_to(signed_in, 302)
    assert URI.decode_query(query) == params
    assert get_session(signed_in, :user_id) == user.id

    consent = signed_in |> follow() |> get(redirected_to(signed_in, 302))
    html = html_response(consent, 200)
    assert html =~ "Allow Claude?"
    assert html =~ user.email
    assert html =~ "Approving returns you to <strong>claude.ai</strong>"

    approved =
      consent
      |> follow()
      |> post(
        ~p"/oauth/authorize",
        Map.merge(params, %{"_csrf_token" => csrf_token(html), "decision" => "approve"})
      )

    assert "https://claude.ai/api/mcp/auth_callback?" <> _ = redirected_to(approved, 302)
    assert %{"code" => code, "state" => state} = redirect_query(approved)
    assert state == params["state"]

    response = exchange_code(client, code, verifier)

    assert %{
             "access_token" => access_token,
             "refresh_token" => refresh_token,
             "token_type" => "Bearer",
             "expires_in" => 3600
           } = json_response(response, 200)

    assert get_resp_header(response, "cache-control") == ["no-store"]

    assert [%Token{} = token] = Repo.all(Token)
    assert token.user_id == user.id
    assert token.access_token_hash == sha256_hex(access_token)
    assert token.refresh_token_hash == sha256_hex(refresh_token)
    assert_in_delta DateTime.diff(token.expires_at, DateTime.utc_now()), 3600, 5
  end

  test "the OAuth sign-in also signs the browser in to the dashboard", %{
    user: user,
    params: params
  } do
    approved = approve(user, params)

    assert %{"email" => email} = approved |> follow() |> get(~p"/api/me") |> json_response(200)
    assert email == user.email
  end

  test "a user signed in to the dashboard sees only the consent page", %{
    conn: conn,
    user: user,
    params: params
  } do
    html =
      conn
      |> sign_in(user)
      |> browser()
      |> get(~p"/oauth/authorize", params)
      |> html_response(200)

    assert html =~ "Allow Claude?"
    refute html =~ "Password"
  end

  test "a wrong password shows the sign-in page again", %{user: user, params: params} do
    page = get(browser(), ~p"/oauth/authorize", params)

    conn =
      page
      |> follow()
      |> post(
        ~p"/oauth/sign_in",
        Map.merge(params, %{
          "_csrf_token" => csrf_token(html_response(page, 200)),
          "email" => user.email,
          "password" => "not the password"
        })
      )

    assert html_response(conn, 401) =~ "Invalid email or password"
    assert get_session(conn, :user_id) == nil
  end

  test "deny redirects with access_denied and the state", %{
    conn: conn,
    user: user,
    params: params
  } do
    consent = conn |> sign_in(user) |> browser() |> get(~p"/oauth/authorize", params)

    denied =
      consent
      |> follow()
      |> post(
        ~p"/oauth/authorize",
        Map.merge(params, %{
          "_csrf_token" => csrf_token(html_response(consent, 200)),
          "decision" => "deny"
        })
      )

    assert redirect_query(denied) == %{"error" => "access_denied", "state" => params["state"]}
  end

  test "a decision posted without a signed-in user shows the sign-in page", %{params: params} do
    page = get(browser(), ~p"/oauth/authorize", params)

    conn =
      page
      |> follow()
      |> post(
        ~p"/oauth/authorize",
        Map.merge(params, %{
          "_csrf_token" => csrf_token(html_response(page, 200)),
          "decision" => "approve"
        })
      )

    assert html_response(conn, 200) =~ "Sign in to Vire"
  end

  test "an unknown client, an unregistered redirect URI or a missing challenge is shown, not redirected",
       %{conn: conn, params: params} do
    for {query, message} <- [
          {%{params | "client_id" => "unknown"}, "is not registered"},
          {Map.delete(params, "client_id"), "does not name an application"},
          {%{params | "redirect_uri" => "https://elsewhere.example/callback"},
           "redirect URI is not registered"},
          {Map.delete(params, "redirect_uri"), "has no redirect URI"},
          {Map.delete(params, "code_challenge"), "no S256 code challenge"},
          {%{params | "code_challenge_method" => "plain"}, "no S256 code challenge"},
          {%{params | "code_challenge" => "short"}, "not an S256 challenge"}
        ] do
      conn = get(conn, ~p"/oauth/authorize", query)

      assert html_response(conn, 400) =~ message
      assert get_resp_header(conn, "location") == []
    end
  end

  test "a wrong response type or resource goes back to the client with the error", %{
    conn: conn,
    params: params
  } do
    for {change, error} <- [
          {%{"response_type" => "token"}, "unsupported_response_type"},
          {%{"resource" => "https://elsewhere.example/mcp"}, "invalid_target"}
        ] do
      conn = get(conn, ~p"/oauth/authorize", Map.merge(params, change))

      assert redirect_query(conn) == %{"error" => error, "state" => params["state"]}
    end
  end

  test "the /mcp URL as the resource and any scope are accepted", %{
    conn: conn,
    user: user,
    params: params
  } do
    params = Map.merge(params, %{"resource" => "http://localhost:4002/mcp", "scope" => "mcp"})

    assert conn
           |> sign_in(user)
           |> browser()
           |> get(~p"/oauth/authorize", params)
           |> html_response(200) =~
             "Allow Claude?"
  end

  test "the sign-in and consent forms refuse a post without the CSRF token", %{
    conn: conn,
    user: user,
    params: params
  } do
    signed_in = conn |> sign_in(user) |> browser()

    assert_error_sent 403, fn ->
      post(browser(), ~p"/oauth/sign_in", Map.merge(params, %{"email" => user.email}))
    end

    assert_error_sent 403, fn ->
      post(signed_in, ~p"/oauth/authorize", Map.put(params, "decision", "approve"))
    end

    assert Repo.aggregate(Vire.Mcp.AuthorizationCode, :count) == 0
  end

  test "the pages forbid framing and every source but their own stylesheet", %{params: params} do
    conn = get(browser(), ~p"/oauth/authorize", params)

    [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "default-src 'none'"
    assert policy =~ "frame-ancestors 'none'"
    [_, style] = Regex.run(~r{<style>(.*)</style>}s, html_response(conn, 200))
    assert policy =~ "style-src 'sha256-#{Base.encode64(:crypto.hash(:sha256, style))}'"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "the client's name is escaped", %{conn: conn, user: user} do
    client = register_client(%{"client_name" => "<script>alert(1)</script>"})
    {_verifier, challenge} = pkce()

    html =
      conn
      |> sign_in(user)
      |> get(~p"/oauth/authorize", authorize_params(client, challenge))
      |> html_response(200)

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end

  defp sha256_hex(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)
end
