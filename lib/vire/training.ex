defmodule Vire.Training do
  @moduledoc """
  The training plan. A season splits into phases, a phase into blocks, a block
  into cycles, and a cycle into one day per date, which holds the day's
  sessions.

  Every function takes a scope first and touches only its user's rows. A row
  of another user reads as `nil` or an empty list and fails a write with
  `{:error, :not_found}`. Every write is logged with a reason: a created row
  keeps its own rationale in `attrs`, which is also the reason unless one is
  given, and an update or delete takes the reason for the change as its last
  argument.
  """

  import Ecto.Query

  alias Vire.Accounts.Scope
  alias Vire.Activities.Activity
  alias Vire.Ingest
  alias Vire.Repo
  alias Vire.Training.Block
  alias Vire.Training.Constraints
  alias Vire.Training.Cycle
  alias Vire.Training.Day
  alias Vire.Training.Matcher
  alias Vire.Training.Period
  alias Vire.Training.Phase
  alias Vire.Training.PlanChange
  alias Vire.Training.Season
  alias Vire.Training.Session

  @match_lock_space 1_098_215_014

  ## Reads

  @doc "The scope's seasons, earliest first."
  def list_seasons(%Scope{} = scope) do
    Season
    |> for_user(scope)
    |> order_by(:period)
    |> Repo.all()
  end

  @doc """
  The start and end of each of the scope's rows of `level`, `:season`,
  `:phase`, `:block` or `:cycle`, earliest first.
  """
  def list_periods(%Scope{} = scope, level) do
    level
    |> schema()
    |> for_user(scope)
    |> order_by(:period)
    |> select([row], row.period)
    |> Repo.all()
  end

  @doc """
  The plan from season down to sessions, each level in date order.

  Given a season id, returns that season with everything beneath it, or `nil`.
  Given a period, returns the seasons that overlap it, with the phases, blocks,
  cycles and days beneath them that overlap it too. Given `nil`, returns every
  season with everything beneath it.
  """
  def get_plan(%Scope{} = scope, nil) do
    Season
    |> for_user(scope)
    |> order_by(:period)
    |> Repo.all()
    |> Repo.preload(plan_preloads(scope, nil))
  end

  def get_plan(%Scope{} = scope, %Period{} = period) do
    Season
    |> for_user(scope)
    |> overlapping(period)
    |> order_by(:period)
    |> Repo.all()
    |> Repo.preload(plan_preloads(scope, period))
  end

  def get_plan(%Scope{} = scope, season_id) do
    case fetch(scope, Season, season_id) do
      nil -> nil
      season -> Repo.preload(season, plan_preloads(scope, nil))
    end
  end

  @doc """
  The day on `date`, with the cycle, block, phase and season above it as
  `context` and its sessions in position order, or `nil`.
  """
  def get_day(%Scope{} = scope, %Date{} = date) do
    scope
    |> day_on(date)
    |> Repo.preload([:context, sessions: sessions_query(scope)])
  end

  @doc """
  The activities that could be each of the scope's `sessions`, by session id:
  for a session without an activity that is not skipped, the unmatched
  activities on its date that `Vire.Training.Matcher` gives any confidence,
  most likely first, each as its `activity_id`, `confidence` and `why`.
  Each session needs its `id` and `date`.
  """
  def list_candidates(%Scope{} = scope, sessions) do
    dates = sessions |> Enum.map(& &1.date) |> Enum.uniq()

    open =
      from(s in for_user(Session, scope),
        join: d in assoc(s, :day),
        where: d.day in ^dates and is_nil(s.activity_id) and s.status != :skipped,
        order_by: s.position,
        select: %{s | date: d.day}
      )
      |> Repo.all()
      |> Enum.group_by(& &1.date)

    activities =
      scope
      |> unmatched_activities(dates)
      |> Repo.all()
      |> Enum.group_by(& &1.local_date)

    wanted = MapSet.new(sessions, & &1.id)

    open
    |> Enum.flat_map(fn {date, sessions} ->
      Matcher.score(Map.get(activities, date, []), sessions)
    end)
    |> Enum.filter(&(MapSet.member?(wanted, &1.session_id) and &1.confidence > 0))
    |> Enum.sort_by(& &1.confidence, :desc)
    |> Enum.group_by(& &1.session_id, &Map.take(&1, [:activity_id, :confidence, :why]))
  end

  @doc """
  What became of each cycle's sessions, by cycle id: how many are planned,
  done and skipped, how many of the planned ones lie before `today`, and the
  seconds planned against the seconds of the matched activities.
  """
  def cycle_summaries(%Scope{} = scope, cycle_ids, %Date{} = today) do
    rows =
      Repo.all(
        from s in for_user(Session, scope),
          join: d in assoc(s, :day),
          left_join: a in Activity,
          on: a.id == s.activity_id,
          where: d.cycle_id in ^cycle_ids,
          select: {d.cycle_id, d.day, s.status, s.planned_seconds, a.duration_seconds}
      )
      |> Enum.group_by(&elem(&1, 0))

    Map.new(cycle_ids, fn id -> {id, summary(Map.get(rows, id, []), today)} end)
  end

  defp summary(rows, today) do
    count = fn keep -> Enum.count(rows, keep) end

    %{
      sessions: %{
        planned: count.(&match?({_, _, :planned, _, _}, &1)),
        done: count.(&match?({_, _, :done, _, _}, &1)),
        skipped: count.(&match?({_, _, :skipped, _, _}, &1)),
        unmatched:
          count.(fn {_, day, status, _, _} -> status == :planned and Date.before?(day, today) end)
      },
      seconds: %{
        planned: Enum.sum_by(rows, &(elem(&1, 3) || 0)),
        actual: Enum.sum_by(rows, &(elem(&1, 4) || 0))
      }
    }
  end

  ## Batches

  @doc """
  Runs `writes`, a function of no arguments answering `{:ok, result}` or
  `{:error, reason}`, as one transaction whose plan rules are checked once it
  has run, so one write may pass through a state a later one settles.

  Before the check, every cycle gains a rest day for each of its dates
  without one, which a cycle widened onto dates another cycle still held
  before narrowing misses. A broken rule rolls everything back and answers
  `{:error, {:periods, violations, result}}` with the result `writes`
  answered, each violation naming the `level` and `id` of the row whose
  period breaks it, with a `message`.
  """
  def batch(%Scope{} = scope, writes) do
    Repo.transact(fn ->
      Repo.query!("set constraints all deferred")

      with {:ok, result} <- writes.(),
           :ok <- fill_days(scope) do
        checked(scope, result)
      end
    end)
  end

  defp checked(scope, result) do
    case period_violations(scope) do
      [] ->
        Repo.query!("set constraints all immediate")
        {:ok, result}

      violations ->
        {:error, {:periods, violations, result}}
    end
  end

  defp fill_days(%Scope{user: user}) do
    Repo.query!(
      """
      insert into training_days (id, user_id, cycle_id, day, kind)
      select gen_random_uuid(), c.user_id, c.id, g.day::date, 'rest'
        from training_cycles c,
             generate_series(lower(c.period), upper(c.period) - 1, interval '1 day') g(day)
        where c.user_id = $1
      on conflict (user_id, day) do nothing
      """,
      [Ecto.UUID.dump!(user.id)]
    )

    :ok
  end

  @levels [
    {:season, "training_seasons", "user_id", nil},
    {:phase, "training_phases", "season_id", {:season, "training_seasons"}},
    {:block, "training_blocks", "phase_id", {:phase, "training_phases"}},
    {:cycle, "training_cycles", "block_id", {:block, "training_blocks"}}
  ]

  defp period_violations(%Scope{user: user}) do
    user_id = Ecto.UUID.dump!(user.id)

    outside =
      for {level, table, key, {parent, parent_table}} <- @levels,
          [id, first, last, parent_id, parent_first, parent_last] <-
            rows(
              """
              select c.id, lower(c.period), upper(c.period) - 1,
                     p.id, lower(p.period), upper(p.period) - 1
                from #{table} c join #{parent_table} p on p.id = c.#{key}
                where c.user_id = $1 and not p.period @> c.period
              """,
              user_id
            ),
          violation <- [
            violation(
              level,
              id,
              "#{dates(first, last)} lies outside its #{parent}, " <>
                dates(parent_first, parent_last)
            ),
            violation(
              parent,
              parent_id,
              "#{dates(parent_first, parent_last)} no longer " <>
                "holds its #{level} of #{dates(first, last)}"
            )
          ],
          do: violation

    overlapping =
      for {level, table, key, _parent} <- @levels,
          [id, other_first, other_last] <-
            rows(
              """
              select a.id, lower(b.period), upper(b.period) - 1
                from #{table} a join #{table} b
                  on b.#{key} = a.#{key} and b.id <> a.id and b.period && a.period
                where a.user_id = $1
              """,
              user_id
            ),
          do: violation(level, id, "overlaps another #{level}, #{dates(other_first, other_last)}")

    stranded =
      for [id, date] <-
            rows(
              """
              select c.id, d.day
                from training_days d join training_cycles c on c.id = d.cycle_id
                where d.user_id = $1 and not c.period @> d.day
              """,
              user_id
            ),
          do:
            violation(
              :cycle,
              id,
              "no longer holds #{date}, a day with a session or a note"
            )

    outside ++ overlapping ++ stranded
  end

  defp rows(sql, user_id), do: Repo.query!(sql, [user_id]).rows

  defp violation(level, id, message),
    do: %{level: level, id: Ecto.UUID.load!(id), message: message}

  defp dates(first, last), do: "#{first} to #{last}"

  ## Seasons, phases, blocks and cycles

  @doc """
  Creates a season from a name, a period and a rationale, and enqueues a
  Garmin sync of its dates for a user with an unpaused Garmin connection.
  """
  def create_season(%Scope{user: user} = scope, attrs, reason \\ nil) do
    changeset = Season.changeset(%Season{user_id: user.id}, attrs)

    logged(scope, nil, reason, fn ->
      with {:ok, season} <- Repo.insert(changeset) do
        request_sync(scope, season.period)
        {:ok, season}
      end
    end)
  end

  @doc "Creates a phase in a season from a name, a period and a rationale."
  def create_phase(%Scope{} = scope, season_id, attrs, reason \\ nil) do
    with {:ok, season} <- fetch_for_write(scope, Season, season_id) do
      changeset = Phase.changeset(%Phase{user_id: season.user_id, season_id: season.id}, attrs)
      logged(scope, nil, reason, fn -> Repo.insert(changeset) end)
    end
  end

  @doc "Creates a block in a phase from a focus, a period and a rationale."
  def create_block(%Scope{} = scope, phase_id, attrs, reason \\ nil) do
    with {:ok, phase} <- fetch_for_write(scope, Phase, phase_id) do
      changeset = Block.changeset(%Block{user_id: phase.user_id, phase_id: phase.id}, attrs)
      logged(scope, nil, reason, fn -> Repo.insert(changeset) end)
    end
  end

  @doc """
  Creates a cycle in a block from a kind, a period and a rationale, with one
  rest day per date, and answers it with its days. Without a period the cycle
  runs from the day after the block's latest cycle, or the block's first day,
  through the following Sunday, within the block.
  """
  def create_cycle(%Scope{} = scope, block_id, attrs, reason \\ nil) do
    with {:ok, block} <- fetch_for_write(scope, Block, block_id) do
      changeset =
        Cycle.create_changeset(
          %Cycle{user_id: block.user_id, block_id: block.id},
          attrs,
          next_cycle_period(block)
        )

      logged(scope, nil, reason, fn -> changeset |> Repo.insert() |> with_days() end)
    end
  end

  @doc """
  Changes a season's name, period or rationale. A period that gains dates
  enqueues a Garmin sync of the dates it gained, for a user with an unpaused
  Garmin connection.
  """
  def update_season(%Scope{} = scope, id, attrs, rationale) do
    with {:ok, season} <- fetch_for_write(scope, Season, id) do
      changeset =
        season
        |> Season.changeset(attrs)
        |> Constraints.require_rationale(rationale)

      logged(scope, season, rationale, fn -> update_widening(scope, season, changeset) end)
    end
  end

  @doc "Changes a phase's name, period or rationale."
  def update_phase(%Scope{} = scope, id, attrs, rationale),
    do: update_level(scope, Phase, id, attrs, rationale)

  @doc "Changes a block's focus, period or rationale."
  def update_block(%Scope{} = scope, id, attrs, rationale),
    do: update_level(scope, Block, id, attrs, rationale)

  @doc """
  Changes a cycle's kind, period or rationale, and answers it with its days.
  A wider period gains a rest day per new date. A narrower one removes the
  days it leaves out, and is refused while any of them holds a session.
  """
  def update_cycle(%Scope{} = scope, id, attrs, rationale) do
    with {:ok, cycle} <- fetch_for_write(scope, Cycle, id) do
      changeset =
        cycle
        |> Cycle.changeset(attrs)
        |> Constraints.require_rationale(rationale)

      logged(scope, cycle, rationale, fn ->
        changeset |> update_dropping_days() |> with_days()
      end)
    end
  end

  @doc "Deletes a season and everything beneath it."
  def delete_season(%Scope{} = scope, id, rationale),
    do: delete_level(scope, Season, id, rationale)

  @doc "Deletes a phase and everything beneath it."
  def delete_phase(%Scope{} = scope, id, rationale), do: delete_level(scope, Phase, id, rationale)

  @doc "Deletes a block and everything beneath it."
  def delete_block(%Scope{} = scope, id, rationale), do: delete_level(scope, Block, id, rationale)

  @doc "Deletes a cycle with its days and their sessions."
  def delete_cycle(%Scope{} = scope, id, rationale), do: delete_level(scope, Cycle, id, rationale)

  ## Days and sessions

  @doc "Changes the kind or the note of the day on `date`."
  def update_day(%Scope{} = scope, %Date{} = date, attrs, rationale) do
    case day_on(scope, date) do
      nil ->
        {:error, :not_found}

      day ->
        changeset =
          day
          |> Day.changeset(attrs)
          |> Constraints.require_rationale(rationale)

        logged(scope, day, rationale, fn -> Repo.update(changeset) end)
    end
  end

  @doc """
  Creates a session on the day of its `date`, from a position, a discipline,
  its structure, the planned seconds and a rationale. The day becomes a
  training day.
  """
  def create_session(%Scope{user: user} = scope, attrs, reason \\ nil) do
    placed =
      %Session{user_id: user.id}
      |> Session.changeset(attrs)
      |> place(scope)

    logged(scope, nil, reason, fn -> write_session(placed, &Repo.insert/1) end)
  end

  @doc """
  Changes a session. A new `date` or `position` moves it to that place, and
  the day it lands on becomes a training day. `status` may be set to `:done`
  or `:skipped` by hand.
  """
  def update_session(%Scope{} = scope, id, attrs, rationale) do
    case session_with_date(scope, id) do
      nil ->
        {:error, :not_found}

      session ->
        placed =
          session
          |> Session.changeset(attrs)
          |> Constraints.require_rationale(rationale)
          |> place(scope)

        logged(scope, session, rationale, fn -> write_session(placed, &Repo.update/1) end)
    end
  end

  @doc "Deletes a session."
  def delete_session(%Scope{} = scope, id, rationale) do
    case session_with_date(scope, id) do
      nil -> {:error, :not_found}
      session -> delete_row(scope, session, rationale)
    end
  end

  ## Matching

  @doc """
  Matches the scope's activities on the local `date` to that day's sessions.

  The day's unmatched activities are scored against its unmatched sessions by
  `Vire.Training.Matcher`, and each pair it is sure of is matched, which makes
  the session done. A skipped session, and one whose match was set or cleared
  by hand, is left out. Automatic matches are not logged.
  """
  def match_activities(%Scope{user: user} = scope, %Date{} = date) do
    {:ok, _paired} =
      Repo.transact(fn ->
        lock_matching(user.id)

        sessions = scope |> unmatched_sessions(date) |> Repo.all()
        activities = scope |> unmatched_activities(date) |> Repo.all()

        paired =
          activities
          |> Matcher.score(sessions)
          |> Matcher.pairs()
          |> Enum.map(&match_pair(&1, sessions))

        {:ok, paired}
      end)

    :ok
  end

  @doc """
  Matches the scope's session with `session_id` to the scope's activity with
  `activity_id` on the session's date, making it done, or clears its match
  with `nil`, making it planned. The change is logged with `rationale`.

  An activity on another date is refused with `{:error, :different_date}`.
  """
  def match_session(%Scope{user: user} = scope, session_id, activity_id, rationale) do
    with %Session{} = session <- session_with_date(scope, session_id) || {:error, :not_found},
         {:ok, activity_id} <- activity_on(scope, session.date, activity_id) do
      changeset =
        session
        |> Session.match_changeset(activity_id)
        |> Constraints.require_rationale(rationale)

      logged(scope, session, rationale, fn ->
        lock_matching(user.id)
        Repo.update(changeset)
      end)
    end
  end

  ## Change log

  @doc """
  The scope's plan changes, newest first. `filters` may narrow them to an
  `entity` and an `entity_id`.
  """
  def list_changes(%Scope{} = scope, filters \\ []) do
    filters = Keyword.take(filters, [:entity, :entity_id])

    if Keyword.has_key?(filters, :entity_id) and Ecto.UUID.cast(filters[:entity_id]) == :error do
      []
    else
      PlanChange
      |> for_user(scope)
      |> where(^filters)
      |> order_by(desc: :inserted_at)
      |> Repo.all()
    end
  end

  ## Helpers

  defp match_pair(%{session_id: id, activity_id: activity_id}, sessions) do
    sessions
    |> Enum.find(&(&1.id == id))
    |> Session.match_changeset(activity_id)
    |> Repo.update!()
  end

  defp unmatched_activities(scope, dates) do
    from a in on_local_dates(for_user(Activity, scope), dates),
      as: :activity,
      where: not exists(from s in Session, where: s.activity_id == parent_as(:activity).id),
      order_by: [a.started_at, a.id]
  end

  defp unmatched_sessions(%Scope{user: user} = scope, date) do
    matched_by_hand =
      from c in PlanChange,
        where: c.user_id == ^user.id and c.entity == :training_session and c.action == :update,
        where: c.entity_id == parent_as(:session).id,
        where: fragment("?->'activity_id' is distinct from ?->'activity_id'", c.before, c.after)

    from s in for_user(Session, scope),
      as: :session,
      join: d in assoc(s, :day),
      where: d.day == ^date and is_nil(s.activity_id) and s.status != :skipped,
      where: not exists(matched_by_hand),
      order_by: s.position
  end

  defp activity_on(_scope, _date, nil), do: {:ok, nil}

  defp activity_on(scope, date, activity_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(activity_id),
         %Activity{local_date: local_date} <- Activity |> for_user(scope) |> Repo.get(uuid) do
      if local_date == date, do: {:ok, uuid}, else: {:error, :different_date}
    else
      _missing -> {:error, :not_found}
    end
  end

  # A parse, a provider summary and a hand match can reach the same day at
  # once; the lock keeps them from pairing one activity twice.
  defp lock_matching(user_id),
    do: Repo.query!("select pg_advisory_xact_lock(#{@match_lock_space}, hashtext($1))", [user_id])

  defp update_widening(scope, season, changeset) do
    with {:ok, updated} <- Repo.update(changeset) do
      request_sync(scope, gained(season.period, updated.period))
      {:ok, updated}
    end
  end

  defp request_sync(_scope, nil), do: :ok

  defp request_sync(%Scope{} = scope, %Period{} = period) do
    Ingest.enqueue_sync(scope, period)
    :ok
  end

  # The dates `new` holds and `old` does not, as one period spanning them.
  defp gained(%Period{} = old, %Period{} = new) do
    earlier =
      if Date.before?(new.first, old.first),
        do: Period.new(new.first, Enum.min([new.last, Date.add(old.first, -1)], Date))

    later =
      if Date.after?(new.last, old.last),
        do: Period.new(Enum.max([new.first, Date.add(old.last, 1)], Date), new.last)

    case {earlier, later} do
      {nil, later} -> later
      {earlier, nil} -> earlier
      {earlier, later} -> Period.new(earlier.first, later.last)
    end
  end

  defp next_cycle_period(%Block{period: block_period} = block) do
    latest_end =
      Repo.one(
        from c in Cycle,
          where: c.block_id == ^block.id,
          select: max(fragment("upper(?)", c.period))
      )

    first = latest_end || block_period.first
    sunday = Date.add(first, 7 - Date.day_of_week(first))

    if Date.after?(first, block_period.last),
      do: nil,
      else: Period.new(first, Enum.min([sunday, block_period.last], Date))
  end

  defp with_days({:ok, cycle}) do
    add_days(cycle)
    {:ok, Repo.preload(cycle, [days: from(d in Day, order_by: d.day)], force: true)}
  end

  defp with_days(error), do: error

  defp update_dropping_days(%Ecto.Changeset{valid?: true, changes: %{period: period}} = changeset) do
    Repo.delete_all(
      from d in Day,
        as: :day,
        where: d.cycle_id == ^changeset.data.id,
        where: d.day < ^period.first or d.day > ^period.last,
        where: d.kind == :rest and is_nil(d.note),
        where: not exists(from s in Session, where: s.day_id == parent_as(:day).id)
    )

    Repo.update(changeset)
  end

  defp update_dropping_days(changeset), do: Repo.update(changeset)

  defp add_days(%Cycle{period: period} = cycle) do
    Repo.insert_all(
      Day,
      for date <- Date.range(period.first, period.last) do
        %{user_id: cycle.user_id, cycle_id: cycle.id, day: date, kind: :rest}
      end,
      on_conflict: :nothing,
      conflict_target: [:user_id, :day]
    )
  end

  defp update_level(scope, schema, id, attrs, rationale) do
    with {:ok, row} <- fetch_for_write(scope, schema, id) do
      changeset =
        row
        |> schema.changeset(attrs)
        |> Constraints.require_rationale(rationale)

      logged(scope, row, rationale, fn -> Repo.update(changeset) end)
    end
  end

  defp delete_level(scope, schema, id, rationale) do
    with {:ok, row} <- fetch_for_write(scope, schema, id) do
      delete_row(scope, row, rationale)
    end
  end

  defp delete_row(scope, row, rationale) do
    changeset =
      row
      |> Ecto.Changeset.change()
      |> Constraints.require_rationale(rationale)

    logged(scope, row, rationale, fn -> Repo.delete(changeset) end)
  end

  # Runs a write and records its change in one transaction. An insert without
  # a reason of its own logs the new row's rationale.
  defp logged(scope, before, rationale, write) do
    Repo.transact(fn ->
      with {:ok, row} <- write.(),
           {:ok, _change} <- record_change(scope, before, row, rationale) do
        {:ok, row}
      end
    end)
  end

  defp record_change(%Scope{user: user} = scope, before, row, rationale) do
    {action, after_row} =
      cond do
        row.__meta__.state == :deleted -> {:delete, nil}
        before -> {:update, row}
        true -> {:insert, row}
      end

    %PlanChange{
      user_id: user.id,
      entity: PlanChange.entity(row),
      entity_id: row.id,
      action: action,
      before: PlanChange.snapshot(before),
      after: PlanChange.snapshot(after_row),
      rationale: rationale || row.rationale,
      channel: scope.channel,
      mcp_client_id: scope.mcp_client_id
    }
    |> PlanChange.changeset()
    |> Repo.insert()
  end

  defp place(changeset, scope) do
    case Ecto.Changeset.fetch_change(changeset, :date) do
      {:ok, date} -> place_on(changeset, day_on(scope, date))
      :error -> {changeset, nil}
    end
  end

  defp place_on(changeset, nil),
    do: {Ecto.Changeset.add_error(changeset, :date, "is not a day in the plan"), nil}

  defp place_on(changeset, %Day{} = day),
    do: {Ecto.Changeset.put_change(changeset, :day_id, day.id), day}

  defp write_session({changeset, day}, write) do
    with {:ok, session} <- write.(changeset),
         {:ok, _day} <- mark_training(day) do
      {:ok, session}
    end
  end

  defp mark_training(nil), do: {:ok, nil}
  defp mark_training(%Day{kind: :training} = day), do: {:ok, day}

  defp mark_training(%Day{} = day),
    do: day |> Ecto.Changeset.change(kind: :training) |> Repo.update()

  defp fetch_for_write(scope, schema, id) do
    case fetch(scope, schema, id) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  defp fetch(scope, schema, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> schema |> for_user(scope) |> Repo.get(uuid)
      :error -> nil
    end
  end

  defp day_on(scope, date), do: Day |> for_user(scope) |> Repo.get_by(day: date)

  defp session_with_date(scope, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> scope |> sessions_query() |> where([s], s.id == ^uuid) |> Repo.one()
      :error -> nil
    end
  end

  defp sessions_query(scope) do
    from s in for_user(Session, scope),
      join: d in assoc(s, :day),
      order_by: s.position,
      select: %{s | date: d.day}
  end

  defp plan_preloads(scope, period) do
    days =
      Day
      |> for_user(scope)
      |> on_days(period)
      |> order_by(:day)

    [
      phases:
        {level(Phase, scope, period),
         blocks:
           {level(Block, scope, period),
            cycles: {level(Cycle, scope, period), days: {days, sessions: sessions_query(scope)}}}}
    ]
  end

  defp level(schema, scope, period) do
    schema
    |> for_user(scope)
    |> overlapping(period)
    |> order_by(:period)
  end

  defp overlapping(query, nil), do: query

  defp overlapping(query, %Period{} = period),
    do: where(query, [row], fragment("? && ?", row.period, type(^period, Period)))

  defp on_days(query, nil), do: query

  defp on_days(query, %Period{first: first, last: last}),
    do: where(query, [d], d.day >= ^first and d.day <= ^last)

  defp for_user(query, %Scope{user: user}), do: where(query, user_id: ^user.id)

  defp on_local_dates(query, %Date{} = date), do: where(query, [a], a.local_date == ^date)

  defp on_local_dates(query, dates) when is_list(dates),
    do: where(query, [a], a.local_date in ^dates)

  defp schema(:season), do: Season
  defp schema(:phase), do: Phase
  defp schema(:block), do: Block
  defp schema(:cycle), do: Cycle
end
