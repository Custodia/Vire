defmodule Vire.Repo.Migrations.SplitSyncRunStates do
  use Ecto.Migration

  def up do
    execute "alter type sync_run_state rename value 'running' to 'searching'"
    execute "alter type sync_run_state add value 'fetching' after 'searching'"

    alter table(:sync_runs) do
      add :files_parsed, :integer, null: false, default: 0
    end
  end

  def down do
    alter table(:sync_runs) do
      remove :files_parsed
    end

    execute "alter table sync_runs alter column state drop default"
    execute "alter type sync_run_state rename to sync_run_state_split"
    execute "create type sync_run_state as enum ('queued', 'running', 'finished', 'failed')"

    execute """
    alter table sync_runs alter column state type sync_run_state using
      (case state::text when 'searching' then 'running' when 'fetching' then 'running'
       else state::text end)::sync_run_state
    """

    execute "alter table sync_runs alter column state set default 'queued'"
    execute "drop type sync_run_state_split"
  end
end
