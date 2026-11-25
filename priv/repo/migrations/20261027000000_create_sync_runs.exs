defmodule Vire.Repo.Migrations.CreateSyncRuns do
  use Ecto.Migration

  def change do
    execute "create type sync_run_trigger as enum ('manual', 'scheduled', 'plan')",
            "drop type sync_run_trigger"

    execute "create type sync_run_state as enum ('queued', 'running', 'finished', 'failed')",
            "drop type sync_run_state"

    create table(:sync_runs) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :trigger, :sync_run_trigger, null: false
      add :state, :sync_run_state, null: false, default: "queued"
      add :error, :text
      add :new_activity_ids, {:array, :uuid}, null: false, default: []
      add :files_total, :integer, null: false, default: 0
      add :files_fetched, :integer, null: false, default: 0
      add :files_failed, :integer, null: false, default: 0
      add :started_at, :timestamptz
      add :searched_at, :timestamptz
      add :finished_at, :timestamptz

      timestamps()
    end

    create index(:sync_runs, [:user_id, :inserted_at])
  end
end
