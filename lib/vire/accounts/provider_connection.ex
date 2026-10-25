defmodule Vire.Accounts.ProviderConnection do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  schema "provider_connections" do
    field :provider, Ecto.Enum, values: [:garmin]
    field :credential, Vire.Encrypted, redact: true
    field :credential_expires_on, :date
    field :last_synced_at, :utc_datetime_usec
    field :paused_at, :utc_datetime_usec

    belongs_to :user, Vire.Accounts.User

    timestamps()
  end

  @doc "A changeset for a new connection. The credential is the provider's API key."
  def create_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:provider, :credential, :credential_expires_on])
    |> validate_required([:provider, :credential])
    |> assoc_constraint(:user)
    |> unique_constraint([:user_id, :provider])
  end
end
