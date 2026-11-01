defmodule Vire.Ingest.ParseWorkerTest do
  use Vire.DataCase, async: true
  use Oban.Testing, repo: Vire.Repo

  import Bitwise
  import Ecto.Query

  alias Vire.Activities.Activity
  alias Vire.Activities.ActivityStream
  alias Vire.Activities.Lap
  alias Vire.Activities.Length
  alias Vire.Ingest
  alias Vire.Ingest.ParseWorker
  alias Vire.Ingest.SourceFile

  setup do
    %{scope: scope_fixture()}
  end

  defp streams(activity) do
    ActivityStream
    |> where(activity_id: ^activity.id)
    |> Repo.all()
    |> Map.new(&{&1.channel, &1})
  end

  defp laps(activity),
    do: Lap |> where(activity_id: ^activity.id) |> order_by(:lap_index) |> Repo.all()

  defp lap_values(lap),
    do: Map.drop(lap, [:__meta__, :id, :activity, :inserted_at, :updated_at])

  defp lengths(activity),
    do: Length |> where(activity_id: ^activity.id) |> order_by(:length_index) |> Repo.all()

  describe "the ride" do
    setup %{scope: scope} do
      %{activity: activity_fixture(scope, "ride.fit")}
    end

    test "is a bike activity on its local date", %{activity: activity} do
      assert activity.discipline == :bike
      assert activity.sport == "cycling"
      assert activity.sub_sport == "road"
      assert activity.started_at == ~U[2026-07-15 02:00:00.000000Z]
      assert activity.utc_offset_seconds == -7 * 3600
      assert activity.local_date == ~D[2026-07-14]
      assert activity.duration_seconds == 540
      assert activity.distance_m == 4590.0
      assert activity.pool_length_m == nil
    end

    test "has its two laps", %{activity: activity} do
      assert [first, second] = laps(activity)

      assert %{lap_index: 0, elapsed_seconds: 240, moving_seconds: 240, avg_power: 215} = first
      assert first.started_at == ~U[2026-07-15 02:00:00.000000Z]
      assert first.distance_m == 2053.2
      assert first.avg_speed_mps == 8.555
      assert %{lap_index: 1, elapsed_seconds: 360, moving_seconds: 300} = second
      assert second.started_at == ~U[2026-07-15 02:04:00.000000Z]
      assert lengths(activity) == []
    end

    test "has a stream per channel with its unit, null across the pause", %{activity: activity} do
      streams = streams(activity)

      assert Map.new(streams, fn {channel, stream} -> {channel, stream.unit} end) == %{
               "cadence" => "rpm",
               "distance" => "m",
               "grade" => "%",
               "heart_rate" => "bpm",
               "power" => "watts",
               "speed" => "m/s"
             }

      for {_channel, stream} <- streams do
        assert length(stream.samples) == 600
        assert stream.samples |> Enum.slice(360..419) |> Enum.all?(&is_nil/1)
        assert stream.samples |> Enum.slice(0..359) |> Enum.all?(&is_float/1)
        assert stream.samples |> Enum.slice(420..599) |> Enum.all?(&is_float/1)
      end

      assert Enum.at(streams["power"].samples, 0) == 215.0
      assert Enum.at(streams["heart_rate"].samples, 0) == 138.0
      assert Enum.at(streams["speed"].samples, 0) == 8.5
    end

    test "marks the file processed with the processor version", %{activity: activity} do
      file = Repo.get!(SourceFile, activity.source_file_id)

      assert file.status == :processed
      assert file.processor_version == ParseWorker.processor_version()
      assert file.error == nil
    end
  end

  test "the run is a run with position in degrees and cadence in steps", %{scope: scope} do
    activity = activity_fixture(scope, "run.fit")

    assert activity.discipline == :run
    assert activity.sub_sport == "street"
    assert activity.utc_offset_seconds == 3 * 3600
    assert activity.local_date == ~D[2026-07-16]
    assert activity.duration_seconds == 600
    assert [%{elapsed_seconds: 600}] = laps(activity)

    streams = streams(activity)

    assert %{
             "position_lat" => %{unit: "degrees"},
             "position_long" => %{unit: "degrees"},
             "cadence" => %{unit: "spm"},
             "altitude" => %{unit: "m"},
             "speed" => %{unit: "m/s"},
             "heart_rate" => %{unit: "bpm"},
             "distance" => %{unit: "m"}
           } = streams

    refute Map.has_key?(streams, "fractional_cadence")
    assert_in_delta hd(streams["position_lat"].samples), 60.1699, 0.000_01
    assert_in_delta hd(streams["position_long"].samples), 24.9384, 0.000_01
    assert hd(streams["cadence"].samples) == 169.0
    assert Enum.all?(Map.values(streams), &(length(&1.samples) == 600))
  end

  test "the pool swim has its lengths and laps and no streams", %{scope: scope} do
    activity = activity_fixture(scope, "swim.fit")

    assert activity.discipline == :swim
    assert activity.sport == "swimming"
    assert activity.sub_sport == "lap_swimming"
    assert activity.pool_length_m == 25.0
    assert activity.distance_m == 300.0
    assert activity.duration_seconds == 385
    assert activity.local_date == ~D[2026-01-20]
    assert activity.utc_offset_seconds == 7200

    assert Enum.map(laps(activity), & &1.elapsed_seconds) == [100, 30, 132, 20, 103]

    lengths = lengths(activity)

    assert Enum.map(lengths, & &1.lap_index) == [0, 0, 0, 0, 1, 2, 2, 2, 2, 3, 4, 4, 4, 4]
    assert Enum.count(lengths, & &1.active) == 12

    assert %{active: true, stroke: "freestyle", strokes: 16, elapsed_seconds: 24.0} =
             hd(lengths)

    assert %{active: false, stroke: nil, strokes: nil, elapsed_seconds: 30.0} =
             Enum.at(lengths, 4)

    assert %{stroke: "breaststroke", strokes: 11} = Enum.at(lengths, 5)
    assert streams(activity) == %{}
  end

  test "a corrupt file is marked failed with the error and kept", %{scope: scope} do
    file = source_file_fixture(scope, "corrupt.fit")
    {:ok, _job} = Ingest.enqueue_parse(scope, file)

    assert %{cancelled: 1} = Oban.drain_queue(queue: :ingest)

    stored = Repo.one!(from f in SourceFile, where: f.id == ^file.id, select: {f, f.content})
    assert {%SourceFile{status: :failed, error: "integrity check failed" <> _}, content} = stored
    assert content == fit_fixture("corrupt.fit")
    assert Repo.aggregate(Activity, :count) == 0
  end

  test "a file the decoder reads but holds no activity is marked failed", %{scope: scope} do
    {:stored, file} = Ingest.store_file(scope, header_only_fit(), :fit, :upload)
    {:ok, _job} = Ingest.enqueue_parse(scope, file)

    assert %{cancelled: 1} = Oban.drain_queue(queue: :ingest)

    assert %SourceFile{status: :failed, error: "the file has neither" <> _} =
             Ingest.get_file(scope, file.id)
  end

  test "a file whose parse raises is marked failed with the error", %{scope: scope} do
    {:stored, file} = Ingest.store_file(scope, lap_power_out_of_range_fit(), :fit, :upload)
    {:ok, _job} = Ingest.enqueue_parse(scope, file)

    assert %{cancelled: 1} = Oban.drain_queue(queue: :ingest)

    assert %SourceFile{status: :failed, error: "parsing failed: " <> error} =
             Ingest.get_file(scope, file.id)

    assert error =~ "got 40000"
    assert Repo.aggregate(Activity, :count) == 0
  end

  test "parsing a file again replaces its activity's children", %{scope: scope} do
    activity = activity_fixture(scope, "ride.fit")
    file = Ingest.get_file(scope, activity.source_file_id)
    original_laps = laps(activity)
    original_power = streams(activity)["power"].samples

    Repo.update_all(from(l in Lap, where: l.activity_id == ^activity.id and l.lap_index == 0),
      set: [avg_power: 1]
    )

    Repo.update_all(
      from(s in ActivityStream, where: s.activity_id == ^activity.id and s.channel == "power"),
      set: [samples: [1.0]]
    )

    Repo.insert!(%Lap{
      activity_id: activity.id,
      lap_index: 7,
      started_at: activity.started_at,
      elapsed_seconds: 1
    })

    {:ok, _job} = Ingest.enqueue_parse(scope, file)
    assert %{success: 1} = Oban.drain_queue(queue: :ingest)

    assert [reparsed] = Repo.all(Activity)
    assert reparsed.id == activity.id
    assert Enum.map(laps(reparsed), &lap_values/1) == Enum.map(original_laps, &lap_values/1)

    assert streams(reparsed)["power"].samples == original_power
    assert map_size(streams(reparsed)) == 6
  end

  test "a file has one parse job waiting at a time", %{scope: scope} do
    file = source_file_fixture(scope, "swim.fit")

    {:ok, first} = Ingest.enqueue_parse(scope, file)
    {:ok, second} = Ingest.enqueue_parse(scope, file)

    assert second.id == first.id
    assert second.conflict?
    assert [_job] = all_enqueued(worker: ParseWorker)
  end

  test "only the owner's .fit files are parsed", %{scope: scope} do
    file = source_file_fixture(scope, "swim.fit")
    {:stored, export} = Ingest.store_file(scope, "a workbook", :nutrition_export, :upload)

    assert {:error, :not_parseable} = Ingest.enqueue_parse(scope_fixture(), file)
    assert {:error, :not_parseable} = Ingest.enqueue_parse(scope, export)
    refute_enqueued(worker: ParseWorker)
  end

  test "a job whose file or user is gone is cancelled", %{scope: scope} do
    file = source_file_fixture(scope, "swim.fit")

    assert {:cancel, _} =
             perform_job(ParseWorker, %{
               source_file_id: Ecto.UUID.generate(),
               user_id: scope.user.id
             })

    assert {:cancel, _} =
             perform_job(ParseWorker, %{source_file_id: file.id, user_id: Ecto.UUID.generate()})
  end

  test "files parsed by an older processor version are enqueued again", %{scope: scope} do
    outdated = activity_fixture(scope, "ride.fit")
    current = activity_fixture(scope, "run.fit")
    failed = source_file_fixture(scope, "corrupt.fit")
    {:ok, _job} = Ingest.enqueue_parse(scope, failed)
    Oban.drain_queue(queue: :ingest)

    Repo.update_all(
      from(f in SourceFile, where: f.id in ^[outdated.source_file_id, failed.id]),
      set: [processor_version: ParseWorker.processor_version() - 1]
    )

    assert Ingest.reparse_outdated() == 1

    assert [%{args: %{"source_file_id" => source_file_id}}] =
             all_enqueued(worker: ParseWorker, state: "available")

    assert source_file_id == outdated.source_file_id
    refute source_file_id == current.source_file_id

    assert %{success: 1} = Oban.drain_queue(queue: :ingest)

    assert Repo.get!(SourceFile, outdated.source_file_id).processor_version ==
             ParseWorker.processor_version()
  end

  @crc_table {0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, 0xA001, 0x6C00,
              0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400}

  defp header_only_fit, do: fit_file(<<>>)

  # A record and a lap whose average power is beyond what a lap stores.
  defp lap_power_out_of_range_fit do
    timestamp = 1_100_000_000
    record = <<0x41, 0, 0, 20::little-16, 1, 253, 4, 0x86, 0x01, timestamp::little-32>>

    lap =
      <<0x42, 0, 0, 19::little-16, 2, 253, 4, 0x86, 19, 2, 0x84, 0x02, timestamp::little-32,
        40_000::little-16>>

    fit_file(record <> lap)
  end

  # A valid FIT file holding a file id message followed by `messages`.
  defp fit_file(messages) do
    definition = <<0x40, 0, 0, 0::little-16, 1, 0, 1, 0>>
    file_id = <<0x00, 4>>
    data = definition <> file_id <> messages
    header = <<14, 0x20, 2195::little-16, byte_size(data)::little-32, ".FIT", 0::little-16>>
    body = header <> data
    body <> <<crc(body)::little-16>>
  end

  defp crc(bytes) do
    for <<byte <- bytes>>, reduce: 0 do
      crc -> crc |> crc_step(byte &&& 0xF) |> crc_step(byte >>> 4)
    end
  end

  defp crc_step(crc, nibble) do
    tmp = elem(@crc_table, crc &&& 0xF)
    crc = crc >>> 4 &&& 0x0FFF
    bxor(bxor(crc, tmp), elem(@crc_table, nibble))
  end
end
