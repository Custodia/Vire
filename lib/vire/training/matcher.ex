defmodule Vire.Training.Matcher do
  @moduledoc """
  How likely each of one date's activities is to be each of its sessions of
  the same discipline, and the pairs sure enough to match without asking.

  A pair's confidence, from 0 to 1, weighs three signals:

    * duration: the shorter of the activity's seconds and the session's
      planned seconds over the longer, when the session plans a duration;
    * order: with as many activities as sessions of the discipline that day,
      1 when the activity's place by start time is the session's place by
      position and 0 otherwise; 0.5 when the counts differ;
    * alone: 1 when the pair are the day's only activity and only session of
      the discipline.

  With a planned duration the confidence is 0.7 × duration + 0.2 × order +
  0.1 × alone, and without one 0.8 × order + 0.2 × alone. A pair is matched
  when its confidence is at least 0.8 and leads every other pair of its
  activity or its session by at least 0.15.
  """

  @sure 0.8
  @lead 0.15

  @type scored :: %{
          activity_id: Ecto.UUID.t(),
          session_id: Ecto.UUID.t(),
          confidence: float(),
          why: String.t()
        }

  @doc """
  Scores every pair of `activities` and `sessions` sharing a discipline, all
  on one date, given in start order and in position order. Each needs its id
  and discipline, an activity its `duration_seconds` and a session its
  `planned_seconds`.
  """
  @spec score([map()], [map()]) :: [scored()]
  def score(activities, sessions) do
    sessions = Enum.group_by(sessions, & &1.discipline)

    activities
    |> Enum.group_by(& &1.discipline)
    |> Enum.flat_map(fn {discipline, activities} ->
      score_discipline(activities, Map.get(sessions, discipline, []), discipline)
    end)
  end

  @doc "The scored pairs sure enough to match, at most one per activity and per session."
  @spec pairs([scored()]) :: [scored()]
  def pairs(scored) do
    scored
    |> Enum.filter(&(&1.confidence >= @sure and leads?(&1, scored)))
    |> Enum.sort_by(& &1.confidence, :desc)
    |> Enum.reduce({[], MapSet.new()}, fn pair, {pairs, taken} ->
      if MapSet.member?(taken, pair.activity_id) or MapSet.member?(taken, pair.session_id),
        do: {pairs, taken},
        else:
          {[pair | pairs], taken |> MapSet.put(pair.activity_id) |> MapSet.put(pair.session_id)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp leads?(pair, scored) do
    Enum.all?(scored, fn other ->
      other == pair or
        (other.activity_id != pair.activity_id and other.session_id != pair.session_id) or
        pair.confidence - other.confidence >= @lead
    end)
  end

  defp score_discipline(_activities, [], _discipline), do: []

  defp score_discipline(activities, sessions, discipline) do
    counts = {length(activities), length(sessions)}

    for {activity, activity_place} <- Enum.with_index(activities),
        {session, session_place} <- Enum.with_index(sessions) do
      duration = duration(activity.duration_seconds, session.planned_seconds)
      order = order(counts, activity_place, session_place)
      alone = if counts == {1, 1}, do: 1, else: 0

      %{
        activity_id: activity.id,
        session_id: session.id,
        confidence: confidence(duration, order, alone),
        why: why(discipline, activity, session, counts, order)
      }
    end
  end

  defp duration(actual, planned) when is_integer(planned) and planned > 0 and is_integer(actual),
    do: min(actual, planned) / max(actual, planned)

  defp duration(_actual, _planned), do: nil

  defp order({count, count}, place, place), do: 1
  defp order({count, count}, _activity_place, _session_place), do: 0
  defp order(_counts, _activity_place, _session_place), do: 0.5

  defp confidence(nil, order, alone), do: Float.round(0.8 * order + 0.2 * alone, 2)

  defp confidence(duration, order, alone),
    do: Float.round(0.7 * duration + 0.2 * order + 0.1 * alone, 2)

  defp why(discipline, activity, session, counts, order) do
    Enum.join(
      [
        "#{discipline}",
        minutes(activity.duration_seconds, session.planned_seconds),
        places(discipline, counts, order)
      ],
      ", "
    )
  end

  defp minutes(actual, planned) when is_integer(planned) and planned > 0,
    do: "#{round(actual / 60)} of #{round(planned / 60)} min planned"

  defp minutes(actual, _planned), do: "#{round(actual / 60)} min, none planned"

  defp places(discipline, {1, 1}, _order), do: "the day's only #{discipline}"
  defp places(_discipline, {count, count}, 1), do: "same place in the day"
  defp places(_discipline, {count, count}, 0), do: "another place in the day"

  defp places(_discipline, {activities, sessions}, _order),
    do: "#{activities} recorded for #{sessions} planned that day"
end
