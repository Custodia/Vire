defmodule VireWeb.TrainingJSON do
  @moduledoc """
  The dashboard's JSON for days, sessions and the activities matched to them.
  """

  alias Vire.Activities.Activity
  alias Vire.Training.Day
  alias Vire.Training.Session

  @titles %{
    swim: "Swim",
    bike: "Bike",
    run: "Run",
    strength: "Strength",
    other: "Session"
  }

  @doc """
  A day with the chain above it and its sessions, each with its matched
  activity's summary from `activities`, a map by id.
  """
  def day(%Day{} = day, activities) do
    %{
      id: day.id,
      date: day.day,
      kind: day.kind,
      note: day.note,
      chain: chain(day),
      sessions: Enum.map(day.sessions, &session(&1, Map.get(activities, &1.activity_id)))
    }
  end

  @doc "A session with its title and its matched activity's summary, or `nil`."
  def session(%Session{} = session, activity) do
    %{
      id: session.id,
      position: session.position,
      discipline: session.discipline,
      title: title(session),
      structure: session.structure,
      planned_seconds: session.planned_seconds,
      status: session.status,
      rationale: session.rationale,
      activity: activity && activity_summary(activity)
    }
  end

  def activity_summary(%Activity{} = activity) do
    Map.take(activity, [
      :id,
      :discipline,
      :started_at,
      :utc_offset_seconds,
      :duration_seconds,
      :distance_m,
      :training_load
    ])
  end

  @doc """
  The season, phase, block and cycle above a day loaded with its cycle and
  context, with the day's number within its cycle and the cycle's length.
  """
  def chain(%Day{context: context, cycle: cycle} = day) do
    %{
      season: %{id: context.season_id, name: context.season_name},
      phase: %{id: context.phase_id, name: context.phase_name},
      block: %{id: context.block_id, focus: context.block_focus},
      cycle: %{
        id: cycle.id,
        kind: cycle.kind,
        day_number: Date.diff(day.day, cycle.period.first) + 1,
        length: Date.diff(cycle.period.last, cycle.period.first) + 1
      }
    }
  end

  defp title(%Session{structure: %{"title" => title}}) when is_binary(title) and title != "",
    do: title

  defp title(%Session{discipline: discipline}), do: Map.fetch!(@titles, discipline)
end
