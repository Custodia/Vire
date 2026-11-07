defmodule Vire.Repo.Migrations.DeferPlanPeriodChecks do
  use Ecto.Migration

  # A batch of plan writes defers these checks to its end, so one write may
  # pass through a state the next one settles. Each check reads its row as it
  # stands when it runs, which may be after later writes or a delete.

  @siblings [
    training_seasons: :user_id,
    training_phases: :season_id,
    training_blocks: :phase_id,
    training_cycles: :block_id
  ]

  @within_parent [
    {"phase_within_season", :training_phases, :training_seasons, :season_id},
    {"block_within_phase", :training_blocks, :training_phases, :phase_id},
    {"cycle_within_block", :training_cycles, :training_blocks, :block_id}
  ]

  @contains_children [
    {"season_contains_phases", :training_seasons, :training_phases, :season_id, :period},
    {"phase_contains_blocks", :training_phases, :training_blocks, :phase_id, :period},
    {"block_contains_cycles", :training_blocks, :training_cycles, :block_id, :period},
    {"cycle_contains_days", :training_cycles, :training_days, :cycle_id, :day}
  ]

  def up do
    for {table, key} <- @siblings do
      execute "alter table #{table} drop constraint #{table}_period_overlap"

      execute """
      alter table #{table} add constraint #{table}_period_overlap
        exclude using gist (#{key} with =, period with &&) deferrable initially immediate
      """
    end

    for {name, table, _parent, _key} <- @within_parent, do: drop_trigger(name, table)
    drop_trigger("day_within_cycle", :training_days)
    for {name, table, _child, _key, _column} <- @contains_children, do: drop_trigger(name, table)

    execute """
    create or replace function assert_period_within_parent() returns trigger
    language plpgsql as $$
    declare
      parent_id uuid;
      child     daterange;
      inside    boolean;
    begin
      execute format('select %I, period from %I where id = $1', tg_argv[1], tg_table_name)
        into parent_id, child using new.id;
      if child is null then
        return null;
      end if;
      execute format('select period @> $1 from %I where id = $2', tg_argv[0])
        into inside using child, parent_id;
      if not coalesce(inside, false) then
        raise exception '% % lies outside its %', tg_table_name, new.id, tg_argv[0]
          using errcode = 'check_violation',
                constraint = tg_table_name || '_period_within_parent';
      end if;
      return null;
    end $$
    """

    execute """
    create or replace function assert_day_within_cycle() returns trigger
    language plpgsql as $$
    declare
      inside boolean;
    begin
      select c.period @> d.day into inside
        from training_days d join training_cycles c on c.id = d.cycle_id
        where d.id = new.id;
      if inside is null and not exists (select 1 from training_days where id = new.id) then
        return null;
      end if;
      if not coalesce(inside, false) then
        raise exception 'training_days % lies outside its cycle', new.id
          using errcode = 'check_violation',
                constraint = 'training_days_day_within_cycle';
      end if;
      return null;
    end $$
    """

    execute """
    create or replace function assert_children_within_period() returns trigger
    language plpgsql as $$
    declare
      own     daterange;
      outside boolean;
    begin
      execute format('select period from %I where id = $1', tg_table_name) into own using new.id;
      if own is null then
        return null;
      end if;
      execute format('select exists (select 1 from %I where %I = $1 and not ($2 @> %I))',
                     tg_argv[0], tg_argv[1], tg_argv[2])
        into outside using new.id, own;
      if outside then
        raise exception '% % no longer contains all of its %', tg_table_name, new.id, tg_argv[0]
          using errcode = 'check_violation',
                constraint = tg_table_name || '_period_contains_children';
      end if;
      return null;
    end $$
    """

    for {name, table, parent, key} <- @within_parent do
      execute """
      create constraint trigger #{name}
        after insert or update of period, #{key} on #{table}
        deferrable initially immediate for each row
        execute function assert_period_within_parent('#{parent}', '#{key}')
      """
    end

    execute """
    create constraint trigger day_within_cycle
      after insert or update of day, cycle_id on training_days
      deferrable initially immediate for each row
      execute function assert_day_within_cycle()
    """

    for {name, table, child, key, column} <- @contains_children do
      execute """
      create constraint trigger #{name}
        after update of period on #{table}
        deferrable initially immediate for each row
        execute function assert_children_within_period('#{child}', '#{key}', '#{column}')
      """
    end
  end

  def down do
    for {table, key} <- @siblings do
      execute "alter table #{table} drop constraint #{table}_period_overlap"

      execute """
      alter table #{table} add constraint #{table}_period_overlap
        exclude using gist (#{key} with =, period with &&)
      """
    end

    for {name, table, _parent, _key} <- @within_parent, do: drop_trigger(name, table)
    drop_trigger("day_within_cycle", :training_days)
    for {name, table, _child, _key, _column} <- @contains_children, do: drop_trigger(name, table)

    execute """
    create or replace function assert_period_within_parent() returns trigger
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
    """

    execute """
    create or replace function assert_day_within_cycle() returns trigger
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
    """

    execute """
    create or replace function assert_children_within_period() returns trigger
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
    """

    for {name, table, parent, key} <- @within_parent do
      execute """
      create trigger #{name} before insert or update of period, #{key} on #{table}
        for each row execute function assert_period_within_parent('#{parent}', '#{key}')
      """
    end

    execute """
    create trigger day_within_cycle before insert or update of day, cycle_id on training_days
      for each row execute function assert_day_within_cycle()
    """

    for {name, table, child, key, column} <- @contains_children do
      execute """
      create trigger #{name} before update of period on #{table}
        for each row execute function assert_children_within_period('#{child}', '#{key}', '#{column}')
      """
    end
  end

  defp drop_trigger(name, table), do: execute("drop trigger #{name} on #{table}")
end
