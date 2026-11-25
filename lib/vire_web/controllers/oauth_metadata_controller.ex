defmodule VireWeb.OAuthMetadataController do
  use VireWeb, :controller

  alias VireWeb.OAuthURL

  def protected_resource(conn, _params) do
    json(conn, %{
      resource: OAuthURL.resource(),
      authorization_servers: [OAuthURL.issuer()],
      bearer_methods_supported: ["header"],
      resource_name: "Vire"
    })
  end

  def authorization_server(conn, _params) do
    issuer = OAuthURL.issuer()

    json(conn, %{
      issuer: issuer,
      authorization_endpoint: issuer <> "/oauth/authorize",
      token_endpoint: issuer <> "/oauth/token",
      registration_endpoint: issuer <> "/oauth/register",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"]
    })
  end
end
