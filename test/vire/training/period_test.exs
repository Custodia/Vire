defmodule Vire.Training.PeriodTest do
  use Vire.DataCase, async: true

  alias Vire.Training.Period
  alias Vire.Training.Season

  defp cast_period(value) do
    %Season{}
    |> Season.changeset(%{name: "Season", rationale: "Why", period: value})
    |> Ecto.Changeset.apply_action(:insert)
  end

  test "casts from a period, a date range and maps of dates or ISO 8601 strings" do
    expected = period(~D[2026-11-02], ~D[2026-11-08])

    for value <- [
          expected,
          Date.range(~D[2026-11-02], ~D[2026-11-08]),
          %{first: ~D[2026-11-02], last: ~D[2026-11-08]},
          %{"first" => "2026-11-02", "last" => "2026-11-08"}
        ] do
      assert {:ok, %Season{period: ^expected}} = cast_period(value)
    end
  end

  test "rejects a period that ends before it starts" do
    {:error, changeset} = cast_period(%{first: ~D[2026-11-08], last: ~D[2026-11-02]})

    assert %{period: ["must not end before it starts"]} = errors_on(changeset)
  end

  test "rejects values that are not two dates" do
    for value <- [
          "2026-11-02",
          %{first: "2026-11-02"},
          %{first: "2026-11-02", last: "not a date"},
          Date.range(~D[2026-11-08], ~D[2026-11-02], -1)
        ] do
      {:error, changeset} = cast_period(value)
      assert %{period: ["is invalid"]} = errors_on(changeset)
    end
  end

  test "stores the inclusive last date as the exclusive upper bound and reads it back" do
    scope = scope_fixture()
    season = season_fixture(scope, period: period(~D[2026-11-02], ~D[2026-11-02]))

    %{rows: [[lower, upper]]} =
      Repo.query!("select lower(period), upper(period) from training_seasons where id = $1", [
        Ecto.UUID.dump!(season.id)
      ])

    assert {lower, upper} == {~D[2026-11-02], ~D[2026-11-03]}
    assert Repo.get!(Season, season.id).period == period(~D[2026-11-02], ~D[2026-11-02])
  end

  test "loads ranges with either kind of bound and refuses unbounded ones" do
    assert Period.load(%Postgrex.Range{
             lower: ~D[2026-11-01],
             upper: ~D[2026-11-08],
             lower_inclusive: false,
             upper_inclusive: true
           }) == {:ok, period(~D[2026-11-02], ~D[2026-11-08])}

    assert Period.load(%Postgrex.Range{lower: :unbound, upper: ~D[2026-11-08]}) == :error
    assert Period.load(nil) == :error
  end

  test "refuses to dump anything but an ordered period" do
    assert Period.dump(%Period{first: ~D[2026-11-08], last: ~D[2026-11-02]}) == :error
    assert Period.dump(~D[2026-11-02]) == :error
  end
end
