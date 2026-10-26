defmodule VireWeb.OAuthMetadataControllerTest do
  use VireWeb.ConnCase, async: true

  test "the protected resource metadata names /mcp and this server", %{conn: conn} do
    for path <- [
          "/.well-known/oauth-protected-resource",
          "/.well-known/oauth-protected-resource/mcp"
        ] do
      conn = get(conn, path)

      assert json_response(conn, 200) == %{
               "resource" => "http://localhost:4002/mcp",
               "authorization_servers" => ["http://localhost:4002"],
               "bearer_methods_supported" => ["header"],
               "resource_name" => "Vire"
             }

      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    end
  end

  test "the authorization server metadata lists its endpoints and methods", %{conn: conn} do
    conn = get(conn, ~p"/.well-known/oauth-authorization-server")

    assert json_response(conn, 200) == %{
             "issuer" => "http://localhost:4002",
             "authorization_endpoint" => "http://localhost:4002/oauth/authorize",
             "token_endpoint" => "http://localhost:4002/oauth/token",
             "registration_endpoint" => "http://localhost:4002/oauth/register",
             "response_types_supported" => ["code"],
             "grant_types_supported" => ["authorization_code", "refresh_token"],
             "code_challenge_methods_supported" => ["S256"],
             "token_endpoint_auth_methods_supported" => ["none"]
           }
  end

  test "an unknown well-known path answers 404", %{conn: conn} do
    conn = get(conn, "/.well-known/openid-configuration")

    assert json_response(conn, 404)
  end

  test "a browser's preflight to the OAuth endpoints is allowed from any origin", %{conn: conn} do
    for path <- ["/.well-known/oauth-authorization-server", "/oauth/register", "/oauth/token"] do
      conn =
        conn
        |> put_req_header("origin", "http://localhost:6274")
        |> options(path)

      assert response(conn, 204) == ""
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert [methods] = get_resp_header(conn, "access-control-allow-methods")
      assert methods =~ "POST"
    end
  end
end
