defmodule Vire.Ingest.FitActivityTest do
  use ExUnit.Case, async: true

  alias Vire.Ingest.FitActivity

  defp decoded(messages, units \\ %{}), do: %{messages: messages, units: units}

  test "maps FIT sports and sub-sports to disciplines" do
    assert FitActivity.discipline("cycling", "road") == :bike
    assert FitActivity.discipline("cycling", "virtual_activity") == :bike
    assert FitActivity.discipline("running", "trail") == :run
    assert FitActivity.discipline("swimming", "lap_swimming") == :swim
    assert FitActivity.discipline("swimming", "open_water") == :swim
    assert FitActivity.discipline("training", "strength_training") == :strength
    assert FitActivity.discipline("fitness_equipment", "strength_training") == :strength
    assert FitActivity.discipline("hiking", nil) == :other
    assert FitActivity.discipline(nil, nil) == :other
  end

  test "without a session, starts at the first record, in UTC, for the records' span" do
    records = [
      %{"timestamp" => "not a time"},
      %{"timestamp" => "2026-03-01T10:00:00.000Z", "heartRate" => 120},
      %{
        "timestamp" => "2026-03-01T10:00:02.000Z",
        "heartRate" => 122,
        "developerFields" => %{"!!" => 1}
      }
    ]

    assert {:ok, %{activity: activity, streams: [stream]}} =
             FitActivity.from_decoded(decoded(%{"recordMesgs" => records}))

    assert activity.started_at == ~U[2026-03-01 10:00:00.000000Z]
    assert activity.utc_offset_seconds == 0
    assert activity.duration_seconds == 2
    assert activity.discipline == :other
    assert activity.sport == nil
    assert %{channel: "heart_rate", unit: "", samples: [120.0, nil, 122.0]} = stream
  end

  test "rounds a local timestamp a few seconds off to the quarter hour" do
    fit_seconds = DateTime.to_unix(~U[2026-03-01 23:31:00Z]) - 631_065_600

    messages = %{
      "sessionMesgs" => [%{"startTime" => "2026-03-01T23:30:00.000Z", "totalTimerTime" => 60}],
      "activityMesgs" => [
        %{"timestamp" => "2026-03-01T23:31:00.000Z", "localTimestamp" => fit_seconds + 19_803}
      ]
    }

    assert {:ok, %{activity: activity}} = FitActivity.from_decoded(decoded(messages))
    assert activity.utc_offset_seconds == 19_800
    assert activity.local_date == ~D[2026-03-02]
  end

  test "keeps a developer channel that a native field already names out" do
    records = [
      %{
        "timestamp" => "2026-03-01T10:00:00.000Z",
        "power" => 200,
        "developerFields" => %{"Power" => 210, "Form Power" => 55}
      }
    ]

    units = %{
      "recordMesgs" => %{"power" => "watts"},
      "developerFields" => %{"Form Power" => "Watts"}
    }

    assert {:ok, %{streams: streams}} =
             FitActivity.from_decoded(decoded(%{"recordMesgs" => records}, units))

    assert [
             %{channel: "form_power", unit: "Watts", samples: [55.0]},
             %{channel: "power", unit: "watts", samples: [200.0]}
           ] = streams
  end

  test "rejects a file with neither a session nor timed records" do
    assert {:error, "the file has neither a session nor records with a start time"} =
             FitActivity.from_decoded(decoded(%{"fileIdMesgs" => [%{"type" => "activity"}]}))
  end
end
