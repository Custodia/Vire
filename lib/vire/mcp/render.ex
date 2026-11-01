defmodule Vire.Mcp.Render do
  @moduledoc """
  The JSON objects tools answer with: plan rows from season to session, each
  with its rationale and with the levels beneath it when they were loaded,
  and activities with their laps and lengths.
  """

  alias Vire.Activities.Activity
  alias Vire.Training.Block
  alias Vire.Training.Cycle
  alias Vire.Training.Day
  alias Vire.Training.DayContext
  alias Vire.Training.Period
  alias Vire.Training.Phase
  alias Vire.Training.Season
  alias Vire.Training.Session

  @activity_fields [
    :id,
    :started_at,
    :utc_offset_seconds,
    :local_date,
    :discipline,
    :sport,
    :sub_sport,
    :duration_seconds,
    :distance_m,
    :pool_length_m,
    :training_load,
    :provider,
    :external_id,
    :source_file_id
  ]

  def season(%Season{} = season) do
    season
    |> Map.take([:id, :name, :rationale])
    |> Map.put(:period, period(season.period))
    |> with_loaded(:phases, season.phases, &phase/1)
  end

  def phase(%Phase{} = phase) do
    phase
    |> Map.take([:id, :season_id, :name, :rationale])
    |> Map.put(:period, period(phase.period))
    |> with_loaded(:blocks, phase.blocks, &block/1)
  end

  def block(%Block{} = block) do
    block
    |> Map.take([:id, :phase_id, :focus, :rationale])
    |> Map.put(:period, period(block.period))
    |> with_loaded(:cycles, block.cycles, &cycle/1)
  end

  def cycle(%Cycle{} = cycle) do
    cycle
    |> Map.take([:id, :block_id, :kind, :rationale])
    |> Map.put(:period, period(cycle.period))
    |> with_loaded(:days, cycle.days, &day/1)
  end

  def day(%Day{} = day) do
    %{id: day.id, cycle_id: day.cycle_id, date: day.day, kind: day.kind, note: day.note}
    |> with_loaded(:sessions, day.sessions, &session/1)
    |> with_loaded(:chain, day.context, &chain/1)
  end

  def session(%Session{} = session) do
    Map.take(session, [
      :id,
      :day_id,
      :date,
      :position,
      :discipline,
      :structure,
      :planned_seconds,
      :status,
      :activity_id,
      :rationale
    ])
  end

  @doc "An activity's summary, without its laps, lengths or provider summary."
  def activity(%Activity{} = activity), do: Map.take(activity, @activity_fields)

  @doc "An activity's summary with its laps, lengths and provider summary."
  def activity_detail(%Activity{} = activity) do
    activity
    |> activity()
    |> Map.merge(%{
      provider_summary: activity.provider_summary,
      laps:
        Enum.map(
          activity.laps,
          &Map.take(&1, [
            :lap_index,
            :started_at,
            :elapsed_seconds,
            :moving_seconds,
            :distance_m,
            :avg_heart_rate,
            :avg_power,
            :avg_speed_mps
          ])
        ),
      lengths:
        Enum.map(
          activity.lengths,
          &Map.take(&1, [
            :length_index,
            :lap_index,
            :started_at,
            :elapsed_seconds,
            :active,
            :stroke,
            :strokes
          ])
        )
    })
  end

  defp chain(%DayContext{} = context) do
    %{
      season: %{id: context.season_id, name: context.season_name},
      phase: %{id: context.phase_id, name: context.phase_name},
      block: %{id: context.block_id, focus: context.block_focus},
      cycle: %{id: context.cycle_id, kind: context.cycle_kind}
    }
  end

  defp period(%Period{first: first, last: last}), do: %{first: first, last: last}

  defp with_loaded(map, _key, %Ecto.Association.NotLoaded{}, _render), do: map

  defp with_loaded(map, key, rows, render) when is_list(rows),
    do: Map.put(map, key, Enum.map(rows, render))

  defp with_loaded(map, key, nil, _render), do: Map.put(map, key, nil)
  defp with_loaded(map, key, row, render), do: Map.put(map, key, render.(row))
end
