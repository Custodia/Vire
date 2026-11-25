defmodule VireWeb.OAuthTokenControllerTest do
  use VireWeb.ConnCase, async: true

  import Ecto.Query

  alias Vire.Mcp.AuthorizationCode
  alias Vire.Mcp.Token
  alias Vire.Repo

  setup do
    user = user_fixture()
    client = register_client()
    {verifier, challenge} = pkce()
    %{"code" => code} = user |> approve(authorize_params(client, challenge)) |> redirect_query()

    %{user: user, client: client, code: code, verifier: verifier}
  end

  defp refresh(client, refresh_token) do
    token_request(%{
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token,
      "client_id" => client["client_id"]
    })
  end

  defp revoked?(token_response) do
    hash = Base.encode16(:crypto.hash(:sha256, token_response["access_token"]), case: :lower)
    Repo.get_by!(Token, access_token_hash: hash).revoked_at != nil
  end

  defp assert_error(conn, status, error) do
    assert %{"error" => ^error, "error_description" => description} = json_response(conn, status)
    assert is_binary(description)
  end

  test "a wrong verifier is an invalid grant", %{client: client, code: code} do
    {other_verifier, _challenge} = pkce()

    client |> exchange_code(code, other_verifier) |> assert_error(400, "invalid_grant")
    client |> exchange_code(code, "too-short") |> assert_error(400, "invalid_grant")
    assert Repo.aggregate(Token, :count) == 0
  end

  test "a code used twice fails and revokes the tokens it issued", %{
    client: client,
    code: code,
    verifier: verifier
  } do
    first = client |> exchange_code(code, verifier) |> json_response(200)

    client |> exchange_code(code, verifier) |> assert_error(400, "invalid_grant")
    assert revoked?(first)
  end

  test "an expired code is an invalid grant", %{client: client, code: code, verifier: verifier} do
    Repo.update_all(AuthorizationCode, set: [expires_at: DateTime.add(DateTime.utc_now(), -1)])

    client |> exchange_code(code, verifier) |> assert_error(400, "invalid_grant")
  end

  test "the code is bound to its client and redirect URI", %{
    client: client,
    code: code,
    verifier: verifier
  } do
    other = register_client(%{"redirect_uris" => client["redirect_uris"]})

    other |> exchange_code(code, verifier) |> assert_error(400, "invalid_grant")

    token_request(%{
      "grant_type" => "authorization_code",
      "code" => code,
      "code_verifier" => verifier,
      "client_id" => client["client_id"],
      "redirect_uri" => "https://claude.ai/elsewhere"
    })
    |> assert_error(400, "invalid_grant")

    client |> exchange_code("not-a-code", verifier) |> assert_error(400, "invalid_grant")
    assert client |> exchange_code(code, verifier) |> json_response(200)
  end

  test "an unknown client is an invalid client", %{code: code, verifier: verifier} do
    %{"client_id" => "unknown", "redirect_uris" => [redirect_uri()]}
    |> exchange_code(code, verifier)
    |> assert_error(401, "invalid_client")
  end

  test "a refresh rotates the pair and revokes the old one", %{
    client: client,
    code: code,
    verifier: verifier
  } do
    first = client |> exchange_code(code, verifier) |> json_response(200)

    second = client |> refresh(first["refresh_token"]) |> json_response(200)

    assert %{"token_type" => "Bearer", "expires_in" => 3600} = second
    assert second["access_token"] != first["access_token"]
    assert second["refresh_token"] != first["refresh_token"]
    assert revoked?(first)
    refute revoked?(second)
  end

  test "a refresh token used twice fails and revokes the pair it was rotated into", %{
    client: client,
    code: code,
    verifier: verifier
  } do
    first = client |> exchange_code(code, verifier) |> json_response(200)
    second = client |> refresh(first["refresh_token"]) |> json_response(200)

    client |> refresh(first["refresh_token"]) |> assert_error(400, "invalid_grant")
    assert revoked?(second)
    client |> refresh(second["refresh_token"]) |> assert_error(400, "invalid_grant")
  end

  test "a refresh token is bound to its client and lasts thirty days", %{
    client: client,
    code: code,
    verifier: verifier
  } do
    first = client |> exchange_code(code, verifier) |> json_response(200)

    register_client() |> refresh(first["refresh_token"]) |> assert_error(400, "invalid_grant")
    client |> refresh("not-a-token") |> assert_error(400, "invalid_grant")

    from(t in Token)
    |> Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(), -30 * 24 * 3600)])

    client |> refresh(first["refresh_token"]) |> assert_error(400, "invalid_grant")
  end

  test "malformed requests follow RFC 6749", %{client: client} do
    token_request(%{}) |> assert_error(400, "invalid_request")
    token_request(%{"grant_type" => "password"}) |> assert_error(400, "unsupported_grant_type")

    token_request(%{"grant_type" => "authorization_code", "client_id" => client["client_id"]})
    |> assert_error(400, "invalid_request")

    token_request(%{"grant_type" => "refresh_token", "refresh_token" => "x"})
    |> assert_error(400, "invalid_request")
  end
end
