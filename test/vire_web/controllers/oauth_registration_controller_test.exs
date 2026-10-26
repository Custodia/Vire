defmodule VireWeb.OAuthRegistrationControllerTest do
  use VireWeb.ConnCase, async: true

  defp register(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/oauth/register", Jason.encode!(body))
  end

  test "registers a public client and answers its id without a secret", %{conn: conn} do
    conn =
      register(conn, %{
        client_name: "Claude",
        redirect_uris: ["https://claude.ai/api/mcp/auth_callback"],
        token_endpoint_auth_method: "none"
      })

    assert %{
             "client_id" => client_id,
             "client_id_issued_at" => issued_at,
             "client_name" => "Claude",
             "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
             "grant_types" => ["authorization_code", "refresh_token"],
             "response_types" => ["code"],
             "token_endpoint_auth_method" => "none"
           } = body = json_response(conn, 201)

    refute Map.has_key?(body, "client_secret")
    assert is_integer(issued_at)
    assert %{name: "Claude", client_secret_hash: nil} = Vire.Mcp.get_client(client_id)
  end

  test "accepts http redirect URIs on localhost and 127.0.0.1", %{conn: conn} do
    uris = ["http://localhost:6274/oauth/callback", "http://127.0.0.1:33418/callback"]

    assert %{"redirect_uris" => ^uris} =
             conn
             |> register(%{client_name: "Inspector", redirect_uris: uris})
             |> json_response(201)
  end

  test "refuses redirect URIs that are not https or local http", %{conn: conn} do
    for uri <- [
          "http://coach.example/callback",
          "cursor://anysphere.cursor-retrieval/callback",
          "https://coach.example/callback#fragment",
          "https:///callback",
          "not a uri"
        ] do
      assert %{"error" => "invalid_redirect_uri"} =
               conn
               |> register(%{client_name: "Coach", redirect_uris: [uri]})
               |> json_response(400)
    end

    for uris <- [nil, [], "https://coach.example/callback"] do
      assert %{"error" => "invalid_redirect_uri"} =
               conn
               |> register(%{client_name: "Coach", redirect_uris: uris})
               |> json_response(400)
    end
  end

  test "requires a client name", %{conn: conn} do
    assert %{
             "error" => "invalid_client_metadata",
             "error_description" => "client_name can't be blank"
           } =
             conn
             |> register(%{redirect_uris: ["https://coach.example/callback"]})
             |> json_response(400)
  end
end
