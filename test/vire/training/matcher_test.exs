defmodule Vire.Training.MatcherTest do
  use ExUnit.Case, async: true

  alias Vire.Training.Matcher

  defp activity(id, discipline, duration_seconds),
    do: %{id: id, discipline: discipline, duration_seconds: duration_seconds}

  defp session(id, discipline, planned_seconds),
    do: %{id: id, discipline: discipline, planned_seconds: planned_seconds}

  test "a lone pair of matching length is certain" do
    assert [%{confidence: 1.0, why: "bike, 60 of 60 min planned, the day's only bike"} = pair] =
             Matcher.score([activity("a", :bike, 3600)], [session("s", :bike, 3600)])

    assert Matcher.pairs([pair]) == [pair]
  end

  test "a lone pair far apart in length is a candidate only" do
    assert [%{confidence: 0.39, why: "bike, 8 of 60 min planned, the day's only bike"} = pair] =
             Matcher.score([activity("a", :bike, 480)], [session("s", :bike, 3600)])

    assert Matcher.pairs([pair]) == []
  end

  test "pairs only within a discipline" do
    scored =
      Matcher.score(
        [activity("ride", :bike, 3600), activity("swim", :swim, 1800)],
        [session("bike", :bike, 3600), session("run", :run, 1800)]
      )

    assert [%{activity_id: "ride", session_id: "bike"}] = scored
  end

  test "pairs as many activities as sessions in order when lengths agree" do
    scored =
      Matcher.score(
        [activity("morning", :run, 3600), activity("evening", :run, 3500)],
        [session("first", :run, 3600), session("second", :run, 3600)]
      )

    assert scored |> Matcher.pairs() |> Enum.map(&{&1.activity_id, &1.session_id}) ==
             [{"morning", "first"}, {"evening", "second"}]

    assert Enum.find(scored, &(&1.activity_id == "evening" and &1.session_id == "first")).why ==
             "run, 58 of 60 min planned, another place in the day"
  end

  test "matches nothing when two activities fit one session equally" do
    scored =
      Matcher.score(
        [activity("morning", :run, 3600), activity("evening", :run, 3600)],
        [session("only", :run, 3600)]
      )

    assert Enum.map(scored, & &1.confidence) == [0.8, 0.8]
    assert hd(scored).why == "run, 60 of 60 min planned, 2 recorded for 1 planned that day"
    assert Matcher.pairs(scored) == []
  end

  test "without a planned duration pairs by order alone" do
    scored =
      Matcher.score(
        [activity("morning", :run, 3600), activity("evening", :run, 1800)],
        [session("first", :run, nil), session("second", :run, nil)]
      )

    assert Enum.map(scored, & &1.confidence) == [0.8, 0.0, 0.0, 0.8]
    assert hd(scored).why == "run, 60 min, none planned, same place in the day"
    assert length(Matcher.pairs(scored)) == 2
  end
end
