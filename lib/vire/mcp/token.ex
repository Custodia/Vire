defmodule Vire.Mcp.Token do
  @moduledoc false

  use Vire.Schema

  schema "mcp_tokens" do
    field :access_token_hash, :string, redact: true
    field :refresh_token_hash, :string, redact: true
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :user, Vire.Accounts.User
    belongs_to :mcp_client, Vire.Mcp.Client

    timestamps()
  end
end
