defmodule Vire.Repo.Migrations.CreateTrainingPlan do
  use Ecto.Migration

  @bounded "not lower_inf(period) and not upper_inf(period) and not isempty(period)"

  def change do
    execute "create extension if not exists btree_gist", "drop extension if exists btree_gist"

    execute "create type discipline as enum ('swim', 'bike', 'run', 'strength', 'other')",
            "drop type discipline"

    execute "create type training_cycle_kind as enum ('load', 'recovery')",
            "drop type training_cycle_kind"

    execute "create type training_day_kind as enum ('training', 'rest')",
            "drop type training_day_kind"

    execute "create type training_session_status as enum ('planned', 'done', 'skipped')",
            "drop type training_session_status"

    create_period_functions()

    create table(:training_seasons) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :period, :daterange, null: false
      add :rationale, :text, null: false

      timestamps()
    end

    period_constraints(:training_seasons, :user_id)

    create table(:training_phases) do
      add :user_id, :uuid, null: false

      add :season_id,
          references(:training_seasons,
            type: :uuid,
            with: [user_id: :user_id],
            on_delete: :delete_all
          ),
          null: false

      add :name, :text, null: false
      add :period, :daterange, null: false
      add :rationale, :text, null: false

      timestamps()
    end

    period_constraints(:training_phases, :season_id)

    create table(:training_blocks) do
      add :user_id, :uuid, null: false

      add :phase_id,
          references(:training_phases,
            type: :uuid,
            with: [user_id: :user_id],
            on_delete: :delete_all
          ),
          null: false

      add :focus, :text, null: false
      add :period, :daterange, null: false
      add :rationale, :text, null: false

      timestamps()
    end

    period_constraints(:training_blocks, :phase_id)

    create table(:training_cycles) do
      add :user_id, :uuid, null: false

      add :block_id,
          references(:training_blocks,
            type: :uuid,
            with: [user_id: :user_id],
            on_delete: :delete_all
          ),
          null: false

      add :kind, :training_cycle_kind, null: false
      add :period, :daterange, null: false
      add :rationale, :text, null: false

      timestamps()
    end

    period_constraints(:training_cycles, :block_id)

    create table(:training_days) do
      add :user_id, :uuid, null: false

      add :cycle_id,
          references(:training_cycles,
            type: :uuid,
            with: [user_id: :user_id],
            on_delete: :delete_all
          ),
          null: false

      add :day, :date, null: false
      add :kind, :training_day_kind, null: false
      add :note, :text

      timestamps()
    end

    create unique_index(:training_days, [:id, :user_id])
    create unique_index(:training_days, [:user_id, :day])

    create table(:training_sessions) do
      add :user_id, :uuid, null: false

      add :day_id,
          references(:training_days,
            type: :uuid,
            with: [user_id: :user_id],
            on_delete: :delete_all
          ),
          null: false

      add :position, :smallint, null: false
      add :discipline, :discipline, null: false
      add :structure, :jsonb, null: false, default: fragment("'{}'::jsonb")
      add :planned_seconds, :integer
      add :status, :training_session_status, null: false, default: "planned"
      add :activity_id, :uuid
      add :rationale, :text, null: false
      add :review, :text
      add :review_score, :smallint
      add :reviewed_at, :timestamptz

      timestamps()
    end

    create unique_index(:training_sessions, [:id, :user_id])
    create unique_index(:training_sessions, [:day_id, :position])
    create unique_index(:training_sessions, [:activity_id])

    create constraint(:training_sessions, :training_sessions_review_score_range,
             check: "review_score between 1 and 5"
           )

    create constraint(:training_sessions, :training_sessions_matched_session_done,
             check: "activity_id is null or status = 'done'"
           )

    create constraint(:training_sessions, :training_sessions_review_written,
             check: "(review is null) = (reviewed_at is null)"
           )

    create constraint(:training_sessions, :training_sessions_score_with_review,
             check: "review_score is null or review is not null"
           )

    create_period_triggers()

    execute """
            create view training_day_contexts as
              select d.id      as day_id,
                     d.user_id,
                     d.day,
                     d.kind    as day_kind,
                     c.id      as cycle_id,
                     c.kind    as cycle_kind,
                     b.id      as block_id,
                     b.focus   as block_focus,
                     p.id      as phase_id,
                     p.name    as phase_name,
                     s.id      as season_id,
                     s.name    as season_name
              from training_days d
              join training_cycles  c on c.id = d.cycle_id
              join training_blocks  b on b.id = c.block_id
              join training_phases  p on p.id = b.phase_id
              join training_seasons s on s.id = p.season_id
            """,
            "drop view training_day_contexts"
  end

  defp period_constraints(table, sibling_key) do
    create unique_index(table, [:id, :user_id])
    create constraint(table, :"#{table}_period_bounded", check: @bounded)

    create constraint(table, :"#{table}_period_overlap",
             exclude: "gist (#{sibling_key} with =, period with &&)"
           )
  end

  # The triggers raise check violations naming a constraint, so Ecto reports
  # them as changeset errors on the period.
  defp create_period_functions do
    execute """
            create function assert_period_within_parent() returns trigger
            language plpgsql as $$
            declare
              parent_id uuid;
              inside    boolean;
            begin
              execute format('select ($1).%I', tg_argv[1]) into parent_id using new;
              execute format('select period @> $1 from %I where id = $2', tg_argv[0])
                into inside using new.period, parent_id;
              if not coalesce(inside, false) then
                raise exception '% % lies outside its %', tg_table_name, new.id, tg_argv[0]
                  using errcode = 'check_violation',
                        constraint = tg_table_name || '_period_within_parent';
              end if;
              return new;
            end $$
            """,
            "drop function assert_period_within_parent()"

    execute """
            create function assert_day_within_cycle() returns trigger
            language plpgsql as $$
            declare
              inside boolean;
            begin
              select period @> new.day into inside from training_cycles where id = new.cycle_id;
              if not coalesce(inside, false) then
                raise exception 'training_days % lies outside its cycle', new.id
                  using errcode = 'check_violation',
                        constraint = 'training_days_day_within_cycle';
              end if;
              return new;
            end $$
            """,
            "drop function assert_day_within_cycle()"

    execute """
            create function assert_children_within_period() returns trigger
            language plpgsql as $$
            declare
              outside boolean;
            begin
              execute format('select exists (select 1 from %I where %I = $1 and not ($2 @> %I))',
                             tg_argv[0], tg_argv[1], tg_argv[2])
                into outside using new.id, new.period;
              if outside then
                raise exception '% % no longer contains all of its %', tg_table_name, new.id, tg_argv[0]
                  using errcode = 'check_violation',
                        constraint = tg_table_name || '_period_contains_children';
              end if;
              return new;
            end $$
            """,
            "drop function assert_children_within_period()"
  end

  defp create_period_triggers do
    trigger(
      "phase_within_season",
      "before insert or update of period, season_id on training_phases",
      "assert_period_within_parent('training_seasons', 'season_id')"
    )

    trigger(
      "block_within_phase",
      "before insert or update of period, phase_id on training_blocks",
      "assert_period_within_parent('training_phases', 'phase_id')"
    )

    trigger(
      "cycle_within_block",
      "before insert or update of period, block_id on training_cycles",
      "assert_period_within_parent('training_blocks', 'block_id')"
    )

    trigger(
      "day_within_cycle",
      "before insert or update of day, cycle_id on training_days",
      "assert_day_within_cycle()"
    )

    trigger(
      "season_contains_phases",
      "before update of period on training_seasons",
      "assert_children_within_period('training_phases', 'season_id', 'period')"
    )

    trigger(
      "phase_contains_blocks",
      "before update of period on training_phases",
      "assert_children_within_period('training_blocks', 'phase_id', 'period')"
    )

    trigger(
      "block_contains_cycles",
      "before update of period on training_blocks",
      "assert_children_within_period('training_cycles', 'block_id', 'period')"
    )

    trigger(
      "cycle_contains_days",
      "before update of period on training_cycles",
      "assert_children_within_period('training_days', 'cycle_id', 'day')"
    )
  end

  defp trigger(name, timing, function) do
    [_, table] = Regex.run(~r/ on (\w+)$/, timing)

    execute "create trigger #{name} #{timing} for each row execute function #{function}",
            "drop trigger #{name} on #{table}"
  end
end
