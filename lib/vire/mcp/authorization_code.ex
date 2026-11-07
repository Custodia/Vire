defmodule Vire.Mcp.AuthorizationCode do
  @moduledoc false

  use Vire.Schema

  schema "mcp_authorization_codes" do
    field :code_hash, :string, redact: true
    field :code_challenge, :string
    field :redirect_uri, :string
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec

    belongs_to :user, Vire.Accounts.User
    belongs_to :mcp_client, Vire.Mcp.Client

    timestamps(updated_at: false)
  end
end
