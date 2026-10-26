defmodule Vire.Training do
  @moduledoc """
  The training plan. A season splits into phases, a phase into blocks, a block
  into cycles, and a cycle into one day per date, which holds the day's
  sessions.

  Every function takes a scope first and touches only its user's rows. A row
  of another user reads as `nil` or an empty list and fails a write with
  `{:error, :not_found}`. Every write takes a rationale: a created row keeps
  its own in `attrs`, and an update or delete takes the reason for the change
  as its last argument.
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
  The plan from season down to sessions, each level in date order.

  Given a season id, returns that season with everything beneath it, or `nil`.
  Given a period, returns the seasons that overlap it, with the phases, blocks,
  cycles and days beneath them that overlap it too.
  """
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
  The day on `date`, with its cycle, the cycle, block, phase and season above
  it as `context`, and its sessions in position order, or `nil`.
  """
  def get_day(%Scope{} = scope, %Date{} = date) do
    scope
    |> day_on(date)
    |> Repo.preload([:cycle, :context, sessions: sessions_query(scope)])
  end

  @doc """
  The scope's activities on the local `date` that no session is matched to,
  earliest first.
  """
  def list_unmatched_activities(%Scope{} = scope, %Date{} = date) do
    scope |> unmatched_activities(date) |> Repo.all()
  end

  ## Seasons, phases, blocks and cycles

  @doc """
  Creates a season from a name, a period and a rationale, and enqueues a
  Garmin sync of its dates for a user with an unpaused Garmin connection.
  """
  def create_season(%Scope{user: user} = scope, attrs) do
    changeset = Season.changeset(%Season{user_id: user.id}, attrs)

    logged(scope, nil, nil, fn ->
      with {:ok, season} <- Repo.insert(changeset) do
        request_sync(scope, season.period)
        {:ok, season}
      end
    end)
  end

  @doc "Creates a phase in a season from a name, a period and a rationale."
  def create_phase(%Scope{} = scope, season_id, attrs) do
    with {:ok, season} <- fetch_for_write(scope, Season, season_id) do
      changeset = Phase.changeset(%Phase{user_id: season.user_id, season_id: season.id}, attrs)
      logged(scope, nil, nil, fn -> Repo.insert(changeset) end)
    end
  end

  @doc "Creates a block in a phase from a focus, a period and a rationale."
  def create_block(%Scope{} = scope, phase_id, attrs) do
    with {:ok, phase} <- fetch_for_write(scope, Phase, phase_id) do
      changeset = Block.changeset(%Block{user_id: phase.user_id, phase_id: phase.id}, attrs)
      logged(scope, nil, nil, fn -> Repo.insert(changeset) end)
    end
  end

  @doc """
  Creates a cycle in a block from a kind, a period and a rationale, with one
  rest day per date, and answers it with its days. Without a period the cycle
  runs from the day after the block's latest cycle, or the block's first day,
  through the following Sunday, within the block.
  """
  def create_cycle(%Scope{} = scope, block_id, attrs) do
    with {:ok, block} <- fetch_for_write(scope, Block, block_id) do
      changeset =
        Cycle.create_changeset(
          %Cycle{user_id: block.user_id, block_id: block.id},
          attrs,
          next_cycle_period(block)
        )

      logged(scope, nil, nil, fn -> changeset |> Repo.insert() |> with_days() end)
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
  def create_session(%Scope{user: user} = scope, attrs) do
    placed =
      %Session{user_id: user.id}
      |> Session.changeset(attrs)
      |> place(scope)

    logged(scope, nil, nil, fn -> write_session(placed, &Repo.insert/1) end)
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

  For each discipline, the day's unmatched activities by start time are
  paired one to one with its unmatched sessions of that discipline by
  position, when their counts are equal; when they differ, none of that
  discipline is matched. A matched session is done. A session whose match was
  set or cleared by hand is left out. Automatic matches are not logged.
  """
  def match_activities(%Scope{user: user} = scope, %Date{} = date) do
    {:ok, _paired} =
      Repo.transact(fn ->
        lock_matching(user.id)

        sessions =
          scope |> unmatched_sessions(date) |> Repo.all() |> Enum.group_by(& &1.discipline)

        paired =
          scope
          |> unmatched_activities(date)
          |> Repo.all()
          |> Enum.group_by(& &1.discipline)
          |> Enum.flat_map(fn {discipline, activities} ->
            pair(activities, Map.get(sessions, discipline, []))
          end)

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

  @doc """
  Marks the scope's sessions still planned on a date before `today` within
  `periods` as skipped. Returns the number of sessions marked.
  """
  def skip_missed_sessions(%Scope{} = scope, periods, %Date{} = today) do
    Enum.sum_by(periods, fn %Period{first: first, last: last} ->
      {count, _sessions} =
        Repo.update_all(
          from(s in for_user(Session, scope),
            join: d in assoc(s, :day),
            where: s.status == :planned,
            where: d.day >= ^first and d.day <= ^last and d.day < ^today
          ),
          set: [status: :skipped, updated_at: DateTime.utc_now()]
        )

      count
    end)
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

  defp pair(activities, sessions) when length(activities) == length(sessions) do
    Enum.zip_with(activities, sessions, fn activity, session ->
      session |> Session.match_changeset(activity.id) |> Repo.update!()
    end)
  end

  defp pair(_activities, _sessions), do: []

  defp unmatched_activities(scope, date) do
    from a in for_user(Activity, scope),
      as: :activity,
      where: a.local_date == ^date,
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
      where: d.day == ^date and is_nil(s.activity_id),
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

  # Runs a write and records its change in one transaction. An insert's
  # rationale is the new row's own.
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
      rationale: if(before, do: rationale, else: row.rationale),
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
end
