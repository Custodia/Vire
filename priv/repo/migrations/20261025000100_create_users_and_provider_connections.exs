defmodule Vire.Repo.Migrations.CreateUsersAndProviderConnections do
  use Ecto.Migration

  def change do
    execute "create extension if not exists citext", "drop extension if exists citext"
    execute "create type provider as enum ('garmin')", "drop type provider"

    create table(:users) do
      add :email, :citext, null: false
      add :name, :text, null: false
      add :password_hash, :text, null: false

      timestamps()
    end

    create unique_index(:users, [:email])

    create table(:provider_connections) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :provider, :provider, null: false
      add :credential, :bytea, null: false
      add :credential_expires_on, :date
      add :last_synced_at, :timestamptz
      add :paused_at, :timestamptz

      timestamps()
    end

    create unique_index(:provider_connections, [:user_id, :provider])
  end
end
