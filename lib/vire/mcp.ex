defmodule Vire.Mcp do
  @moduledoc """
  MCP clients and the OAuth 2.1 grants that let them act for a user: clients
  registered dynamically, single-use authorization codes bound to a PKCE
  challenge, and access tokens with rotating refresh tokens. Codes and tokens
  are random and only their SHA-256 hashes are stored.
  """

  import Ecto.Query

  alias Vire.Accounts.Scope
  alias Vire.Accounts.User
  alias Vire.Mcp.AuthorizationCode
  alias Vire.Mcp.AuthorizationRequest
  alias Vire.Mcp.Client
  alias Vire.Mcp.Token
  alias Vire.Repo

  @code_seconds 10 * 60
  @access_seconds 60 * 60
  @refresh_seconds 30 * 24 * 60 * 60

  @doc "Registers a public client from its name and redirect URIs."
  def register_client(attrs) do
    %Client{client_id: random_token()}
    |> Client.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns the client registered under `client_id`, or `nil`."
  def get_client(client_id) when is_binary(client_id),
    do: Repo.get_by(Client, client_id: client_id)

  def get_client(_client_id), do: nil

  @doc """
  Issues an authorization code for the scope's user and the request's client,
  valid for ten minutes and exchangeable once.
  """
  def create_authorization_code(
        %Scope{user: %User{id: user_id}},
        %AuthorizationRequest{} = request
      ) do
    code = random_token()

    %AuthorizationCode{
      user_id: user_id,
      mcp_client_id: request.client.id,
      code_hash: hash(code),
      code_challenge: request.code_challenge,
      redirect_uri: request.redirect_uri,
      expires_at: DateTime.add(DateTime.utc_now(), @code_seconds)
    }
    |> Repo.insert!()

    {:ok, code}
  end

  @doc """
  Exchanges an authorization code for an access token and a refresh token.
  The code must be the client's, unused and unexpired, issued for
  `redirect_uri`, and `verifier` must hash to its challenge. A code presented a
  second time revokes every token its user holds for the client.
  """
  def exchange_authorization_code(client_id, code, verifier, redirect_uri) do
    with {:ok, client} <- fetch_client(client_id),
         {:ok, grant} <- fetch_code(code),
         :ok <- check_unused(grant),
         :ok <- check_code(grant, client, redirect_uri, verifier) do
      fn -> grant |> mark_used() |> issue_once(grant) end
      |> Repo.transact()
      |> revoke_on_reuse(grant)
    end
  end

  @doc """
  Exchanges a refresh token for a new pair and revokes the old one. A refresh
  token used a second time revokes every token its user holds for the client.
  """
  def refresh_access_token(client_id, refresh_token) do
    with {:ok, client} <- fetch_client(client_id),
         {:ok, token} <- fetch_refresh_token(refresh_token),
         :ok <- check_token_client(token, client),
         :ok <- check_unrevoked(token),
         :ok <- check_refreshable(token) do
      fn -> token |> revoke() |> issue_once(token) end
      |> Repo.transact()
      |> revoke_on_reuse(token)
    end
  end

  defp fetch_client(client_id) do
    case get_client(client_id) do
      %Client{} = client -> {:ok, client}
      nil -> {:error, :invalid_client}
    end
  end

  defp fetch_code(code) when is_binary(code) do
    case Repo.get_by(AuthorizationCode, code_hash: hash(code)) do
      %AuthorizationCode{} = grant -> {:ok, grant}
      nil -> {:error, :invalid_grant}
    end
  end

  defp check_unused(%AuthorizationCode{used_at: nil}), do: :ok

  defp check_unused(%AuthorizationCode{} = grant) do
    revoke_client_tokens(grant)
    {:error, :invalid_grant}
  end

  defp check_code(grant, client, redirect_uri, verifier) do
    cond do
      DateTime.compare(grant.expires_at, DateTime.utc_now()) != :gt -> {:error, :invalid_grant}
      grant.mcp_client_id != client.id -> {:error, :invalid_grant}
      grant.redirect_uri != redirect_uri -> {:error, :invalid_grant}
      not verifies?(verifier, grant.code_challenge) -> {:error, :invalid_grant}
      true -> :ok
    end
  end

  defp verifies?(verifier, challenge) do
    verifier =~ ~r/\A[A-Za-z0-9._~-]{43,128}\z/ and
      Plug.Crypto.secure_compare(
        Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false),
        challenge
      )
  end

  defp mark_used(grant) do
    AuthorizationCode
    |> where(id: ^grant.id)
    |> where([c], is_nil(c.used_at))
    |> Repo.update_all(set: [used_at: DateTime.utc_now()])
  end

  defp fetch_refresh_token(refresh_token) when is_binary(refresh_token) do
    case Repo.get_by(Token, refresh_token_hash: hash(refresh_token)) do
      %Token{} = token -> {:ok, token}
      nil -> {:error, :invalid_grant}
    end
  end

  defp check_token_client(%Token{mcp_client_id: id}, %Client{id: id}), do: :ok
  defp check_token_client(_token, _client), do: {:error, :invalid_grant}

  defp check_unrevoked(%Token{revoked_at: nil}), do: :ok

  defp check_unrevoked(%Token{} = token) do
    revoke_client_tokens(token)
    {:error, :invalid_grant}
  end

  # The table keeps one expiry, the access token's; a refresh token lasts a
  # fixed time from the row's creation.
  defp check_refreshable(%Token{inserted_at: inserted_at}) do
    if DateTime.diff(DateTime.utc_now(), inserted_at) < @refresh_seconds,
      do: :ok,
      else: {:error, :invalid_grant}
  end

  defp revoke(token) do
    Token
    |> where(id: ^token.id)
    |> where([t], is_nil(t.revoked_at))
    |> Repo.update_all(set: [revoked_at: DateTime.utc_now(), updated_at: DateTime.utc_now()])
  end

  # A grant is consumed by a conditional update; when another request consumed
  # it first, the update touches no row.
  defp issue_once({1, _rows}, grant), do: issue_tokens(grant.user_id, grant.mcp_client_id)
  defp issue_once({0, _rows}, _grant), do: {:error, :reused}

  defp revoke_on_reuse({:error, :reused}, grant) do
    revoke_client_tokens(grant)
    {:error, :invalid_grant}
  end

  defp revoke_on_reuse(result, _grant), do: result

  defp revoke_client_tokens(%{user_id: user_id, mcp_client_id: client_id}) do
    now = DateTime.utc_now()

    Token
    |> where(user_id: ^user_id, mcp_client_id: ^client_id)
    |> where([t], is_nil(t.revoked_at))
    |> Repo.update_all(set: [revoked_at: now, updated_at: now])
  end

  defp issue_tokens(user_id, client_id) do
    access_token = random_token()
    refresh_token = random_token()

    Repo.insert!(%Token{
      user_id: user_id,
      mcp_client_id: client_id,
      access_token_hash: hash(access_token),
      refresh_token_hash: hash(refresh_token),
      expires_at: DateTime.add(DateTime.utc_now(), @access_seconds)
    })

    {:ok,
     %{access_token: access_token, refresh_token: refresh_token, expires_in: @access_seconds}}
  end

  defp random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp hash(secret), do: Base.encode16(:crypto.hash(:sha256, secret), case: :lower)
end
