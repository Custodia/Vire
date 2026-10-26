defmodule Vire.Repo.Migrations.CreateMcpClients do
  use Ecto.Migration

  def change do
    create table(:mcp_clients) do
      add :client_id, :text, null: false
      add :client_secret_hash, :text
      add :name, :text, null: false
      add :redirect_uris, {:array, :text}, null: false

      timestamps()
    end

    create unique_index(:mcp_clients, [:client_id])

    create constraint(:mcp_clients, :mcp_clients_redirect_uris_present,
             check: "cardinality(redirect_uris) > 0"
           )

    create table(:mcp_authorization_codes) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :mcp_client_id, references(:mcp_clients, type: :uuid, on_delete: :delete_all),
        null: false

      add :code_hash, :text, null: false
      add :code_challenge, :text, null: false
      add :redirect_uri, :text, null: false
      add :expires_at, :timestamptz, null: false
      add :used_at, :timestamptz

      timestamps(updated_at: false)
    end

    create unique_index(:mcp_authorization_codes, [:code_hash])

    create table(:mcp_tokens) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :mcp_client_id, references(:mcp_clients, type: :uuid, on_delete: :delete_all),
        null: false

      add :access_token_hash, :text, null: false
      add :refresh_token_hash, :text
      add :expires_at, :timestamptz, null: false
      add :revoked_at, :timestamptz

      timestamps()
    end

    create unique_index(:mcp_tokens, [:access_token_hash])
    create unique_index(:mcp_tokens, [:refresh_token_hash])
    create index(:mcp_tokens, [:user_id, "inserted_at desc"], name: :mcp_tokens_user)

    alter table(:plan_changes) do
      modify :mcp_client_id,
             references(:mcp_clients, type: :uuid, on_delete: :nilify_all, validate: false),
             from: :uuid
    end
  end
end
