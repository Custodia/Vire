defmodule VireWeb.OAuthFlow do
  @moduledoc """
  Drives the OAuth flow an MCP client runs, through the real endpoint: dynamic
  registration, the sign-in and consent pages, and the token exchange.
  """

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint VireWeb.Endpoint

  @redirect_uri "https://claude.ai/api/mcp/auth_callback"

  def redirect_uri, do: @redirect_uri

  @doc """
  A connection that checks CSRF tokens the way a browser's request is checked.
  Phoenix's test connections skip the check.
  """
  def browser(conn \\ build_conn()), do: put_private(conn, :plug_skip_csrf_protection, false)

  @doc "The browser's next request, carrying the cookies `conn` set."
  def follow(conn), do: conn |> recycle() |> browser()

  @doc "Registers a client and answers the registration response."
  def register_client(attrs \\ %{}) do
    body = Map.merge(%{"client_name" => "Coach", "redirect_uris" => [@redirect_uri]}, attrs)

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post("/oauth/register", Jason.encode!(body))
    |> json_response(201)
  end

  @doc "A PKCE verifier and its S256 challenge."
  def pkce do
    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    {verifier, Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)}
  end

  @doc "The query of an authorization request for `client` with `challenge`."
  def authorize_params(client, challenge, extra \\ %{}) do
    Map.merge(
      %{
        "response_type" => "code",
        "client_id" => client["client_id"],
        "redirect_uri" => hd(client["redirect_uris"]),
        "code_challenge" => challenge,
        "code_challenge_method" => "S256",
        "state" => "state-#{System.unique_integer([:positive])}"
      },
      extra
    )
  end

  @doc "The CSRF token of the form on an HTML page."
  def csrf_token(html) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html)
    token
  end

  @doc """
  Opens the authorization request in a fresh browser, signs `user` in on the
  sign-in page and approves on the consent page. Answers the approval's
  response, which redirects to the client with the code.
  """
  def approve(user, params) do
    conn = get(browser(), "/oauth/authorize", params)

    conn =
      conn
      |> follow()
      |> post(
        "/oauth/sign_in",
        Map.merge(params, %{
          "_csrf_token" => csrf_token(html_response(conn, 200)),
          "email" => user.email,
          "password" => Vire.AccountsFixtures.valid_password()
        })
      )

    consent = conn |> follow() |> get(redirected_to(conn, 302))

    consent
    |> follow()
    |> post(
      "/oauth/authorize",
      Map.merge(params, %{
        "_csrf_token" => csrf_token(html_response(consent, 200)),
        "decision" => "approve"
      })
    )
  end

  @doc "The query parameters of a response's redirect."
  def redirect_query(conn) do
    conn |> redirected_to(302) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  @doc "Posts a form to the token endpoint and answers the response."
  def token_request(params) do
    post(build_conn(), "/oauth/token", params)
  end

  @doc "Exchanges `code` for tokens as `client` would."
  def exchange_code(client, code, verifier) do
    token_request(%{
      "grant_type" => "authorization_code",
      "code" => code,
      "code_verifier" => verifier,
      "client_id" => client["client_id"],
      "redirect_uri" => hd(client["redirect_uris"])
    })
  end

  @doc """
  Runs the whole flow for `user` with a newly registered client and answers the
  token response with the client's registration under `"client"`.
  """
  def obtain_mcp_token(user) do
    client = register_client()
    {verifier, challenge} = pkce()
    %{"code" => code} = user |> approve(authorize_params(client, challenge)) |> redirect_query()

    client
    |> exchange_code(code, verifier)
    |> json_response(200)
    |> Map.put("client", client)
  end
end
