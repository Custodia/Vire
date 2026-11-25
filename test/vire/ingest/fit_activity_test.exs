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

  test "maps Garmin's activity type keys to disciplines" do
    assert FitActivity.discipline("road_biking", nil) == :bike
    assert FitActivity.discipline("virtual_ride", nil) == :bike
    assert FitActivity.discipline("indoor_cycling", nil) == :bike
    assert FitActivity.discipline("trail_running", nil) == :run
    assert FitActivity.discipline("treadmill_running", nil) == :run
    assert FitActivity.discipline("lap_swimming", nil) == :swim
    assert FitActivity.discipline("open_water_swimming", nil) == :swim
    assert FitActivity.discipline("strength_training", nil) == :strength
    assert FitActivity.discipline("yoga", nil) == :other
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

  describe "trim_to_summary/2" do
    @start ~U[2026-03-01 10:00:00.000000Z]

    defp recording do
      %{
        activity: %{
          started_at: @start,
          utc_offset_seconds: 3600,
          local_date: ~D[2026-03-01],
          duration_seconds: 900,
          distance_m: 2700.0
        },
        laps: [
          lap(0, 0, 300, 900.0),
          lap(1, 300, 600, 1800.0)
        ],
        lengths: [],
        streams: [
          %{channel: "distance", unit: "m", samples: Enum.map(1..900, &(&1 * 3.0))},
          %{
            channel: "heart_rate",
            unit: "bpm",
            samples: Enum.map(0..899, &(100.0 + div(&1, 300)))
          }
        ]
      }
    end

    defp lap(index, from, seconds, distance) do
      %{
        lap_index: index,
        started_at: DateTime.add(@start, from),
        elapsed_seconds: seconds,
        moving_seconds: seconds,
        distance_m: distance,
        avg_heart_rate: 100,
        avg_power: nil,
        avg_speed_mps: 3.0
      }
    end

    defp span(first, last, extra \\ %{}) do
      Map.merge(
        %{
          "startTimeGMT" => Calendar.strftime(DateTime.add(@start, first), "%Y-%m-%d %H:%M:%S"),
          "endTimeGMT" => Calendar.strftime(DateTime.add(@start, last), "%Y-%m-%d %H:%M:%S"),
          "duration" => (last - first) * 1.0,
          "distance" => (last - first) * 3.0
        },
        extra
      )
    end

    test "cuts the recording to a span that ends early" do
      trimmed = FitActivity.trim_to_summary(recording(), span(0, 450, %{"duration" => 440.4}))

      assert trimmed.activity.started_at == @start
      assert trimmed.activity.duration_seconds == 440
      assert trimmed.activity.distance_m == 1350.0
      assert [first, cut] = trimmed.laps
      assert first == lap(0, 0, 300, 900.0)
      assert %{lap_index: 1, elapsed_seconds: 150, moving_seconds: 150, distance_m: 450.0} = cut
      assert cut.avg_heart_rate == 101
      assert cut.avg_speed_mps == 3.0
      assert Enum.all?(trimmed.streams, &(length(&1.samples) == 450))
    end

    test "moves the start to a span that starts late" do
      trimmed = FitActivity.trim_to_summary(recording(), span(600, 900))

      assert trimmed.activity.started_at == DateTime.add(@start, 600)
      assert [%{lap_index: 0, elapsed_seconds: 300, distance_m: 900.0} = lap] = trimmed.laps
      assert lap.started_at == DateTime.add(@start, 600)
      assert [%{samples: [1803.0 | _]}, %{samples: [102.0 | _]}] = trimmed.streams
    end

    test "takes the span's end from its elapsed time without an end" do
      summary = span(0, 450) |> Map.delete("endTimeGMT") |> Map.put("elapsedDuration", 450.2)

      assert %{laps: [_, %{elapsed_seconds: 150}]} =
               FitActivity.trim_to_summary(recording(), summary)
    end

    test "leaves a recording the span covers, or no span, as it is" do
      assert FitActivity.trim_to_summary(recording(), span(0, 901)) == recording()
      assert FitActivity.trim_to_summary(recording(), span(1, 899)) == recording()
      assert FitActivity.trim_to_summary(recording(), nil) == recording()
      assert FitActivity.trim_to_summary(recording(), %{"startTimeGMT" => "soon"}) == recording()
    end
  end
end
