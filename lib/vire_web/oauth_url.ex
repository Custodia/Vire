defmodule VireWeb.OAuthURL do
  @moduledoc """
  The absolute URLs OAuth and MCP clients see, built from the endpoint's
  configured URL so they hold behind a proxy.
  """

  @doc "The authorization server's issuer: the application's base URL."
  def issuer, do: VireWeb.Endpoint.url()

  @doc "The protected resource: the MCP endpoint."
  def resource, do: issuer() <> "/mcp"

  @doc "Where the protected resource metadata is served."
  def resource_metadata, do: issuer() <> "/.well-known/oauth-protected-resource"
end
