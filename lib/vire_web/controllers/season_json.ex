defmodule VireWeb.SeasonJSON do
  @moduledoc """
  The dashboard's JSON for the plan: a season's list entry, and one season with
  the phases, blocks, cycles, days and sessions beneath it and the activities
  on its dates that no session is matched to.
  """

  alias Vire.Training.Block
  alias Vire.Training.Cycle
  alias Vire.Training.Day
  alias Vire.Training.Period
  alias Vire.Training.Phase
  alias Vire.Training.Season
  alias Vire.Training.Session
  alias VireWeb.TrainingJSON

  def index(%{seasons: seasons}), do: %{seasons: Enum.map(seasons, &entry/1)}

  def show(%{season: %Season{} = season, unmatched: unmatched}) do
    season
    |> entry()
    |> Map.merge(%{
      rationale: season.rationale,
      phases: Enum.map(season.phases, &phase/1),
      activities: Enum.map(unmatched, &activity/1)
    })
  end

  defp entry(%Season{} = season),
    do: %{id: season.id, name: season.name, period: period(season.period)}

  defp phase(%Phase{} = phase) do
    %{
      id: phase.id,
      name: phase.name,
      rationale: phase.rationale,
      period: period(phase.period),
      blocks: Enum.map(phase.blocks, &block/1)
    }
  end

  defp block(%Block{} = block) do
    %{
      id: block.id,
      focus: block.focus,
      period: period(block.period),
      cycles: Enum.map(block.cycles, &cycle/1)
    }
  end

  defp cycle(%Cycle{} = cycle) do
    %{
      id: cycle.id,
      kind: cycle.kind,
      period: period(cycle.period),
      days: Enum.map(cycle.days, &day/1)
    }
  end

  defp day(%Day{} = day) do
    %{
      id: day.id,
      date: day.day,
      kind: day.kind,
      note: day.note,
      sessions: Enum.map(day.sessions, &session/1)
    }
  end

  defp session(%Session{} = session) do
    %{
      id: session.id,
      position: session.position,
      discipline: session.discipline,
      title: TrainingJSON.title(session),
      planned_seconds: session.planned_seconds,
      status: session.status
    }
  end

  defp activity(activity) do
    Map.take(activity, [
      :id,
      :discipline,
      :local_date,
      :started_at,
      :utc_offset_seconds,
      :duration_seconds,
      :distance_m,
      :training_load
    ])
  end

  defp period(%Period{first: first, last: last}), do: %{first: first, last: last}
end
