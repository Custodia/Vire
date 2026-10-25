defmodule Vire.Repo.Migrations.CreatePlanChanges do
  use Ecto.Migration

  def change do
    execute """
            create type plan_entity as enum ('training_season', 'training_phase', 'training_block',
                                             'training_cycle', 'training_day', 'training_session',
                                             'training_goal', 'event')
            """,
            "drop type plan_entity"

    execute "create type plan_change_action as enum ('insert', 'update', 'delete')",
            "drop type plan_change_action"

    execute "create type plan_change_channel as enum ('dashboard', 'mcp')",
            "drop type plan_change_channel"

    create table(:plan_changes) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :entity, :plan_entity, null: false
      add :entity_id, :uuid, null: false
      add :action, :plan_change_action, null: false
      add :before, :jsonb
      add :after, :jsonb
      add :rationale, :text, null: false
      add :channel, :plan_change_channel, null: false
      add :mcp_client_id, :uuid

      timestamps(updated_at: false)
    end

    create constraint(:plan_changes, :plan_changes_insert_without_before,
             check: "(action = 'insert') = (before is null)"
           )

    create constraint(:plan_changes, :plan_changes_delete_without_after,
             check: "(action = 'delete') = (after is null)"
           )

    create constraint(:plan_changes, :plan_changes_mcp_names_client,
             check: "(channel = 'mcp') = (mcp_client_id is not null)"
           )

    create index(:plan_changes, [:user_id, :entity, :entity_id, "inserted_at desc"],
             name: :plan_changes_entity
           )

    create index(:plan_changes, [:user_id, "inserted_at desc"], name: :plan_changes_recent)
  end
end
