defmodule Vire.Ingest.DecoderTest do
  use ExUnit.Case, async: true

  alias Vire.Ingest.Decoder

  @fixtures Path.expand("../../support/fixtures/fit", __DIR__)

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp start_decoder(opts \\ []) do
    name = :"decoder_#{System.unique_integer([:positive])}"
    start_supervised!({Decoder, Keyword.put(opts, :name, name)})
    name
  end

  defp await_new_process(server, old_pid) do
    Enum.find_value(1..100, fn _ ->
      case Decoder.os_pid(server) do
        ^old_pid ->
          Process.sleep(20)
          nil

        _other ->
          :restarted
      end
    end)
  end

  test "decodes the ride into its messages, with the developer field named" do
    assert {:ok, %{messages: messages, units: units}} = Decoder.decode(fixture("ride.fit"))

    assert [%{"type" => "activity", "manufacturer" => "development"}] = messages["fileIdMesgs"]
    assert [%{"deviceIndex" => "creator"}] = messages["deviceInfoMesgs"]

    assert [%{"sport" => "cycling", "subSport" => "road", "totalTimerTime" => 540}] =
             messages["sessionMesgs"]

    assert [%{"localTimestamp" => _, "timestamp" => "2026-07-15T02:10:00.000Z"}] =
             messages["activityMesgs"]

    assert length(messages["lapMesgs"]) == 2
    assert length(messages["recordMesgs"]) == 540

    assert Enum.map(messages["eventMesgs"], & &1["eventType"]) ==
             ["start", "stopAll", "start", "stopAll"]

    assert %{
             "timestamp" => "2026-07-15T02:00:00.000Z",
             "power" => 215,
             "heartRate" => 138,
             "developerFields" => %{"Grade" => 0}
           } = hd(messages["recordMesgs"])

    assert %{"heartRate" => "bpm", "power" => "watts", "enhancedSpeed" => "m/s"} =
             units["recordMesgs"]

    assert units["developerFields"] == %{"Grade" => "%"}
  end

  test "decodes the run's position and the swim's lengths" do
    assert {:ok, %{messages: run}} = Decoder.decode(fixture("run.fit"))
    assert {:ok, %{messages: swim}} = Decoder.decode(fixture("swim.fit"))

    assert %{"positionLat" => _, "positionLong" => _, "fractionalCadence" => 0.5} =
             hd(run["recordMesgs"])

    assert [%{"sport" => "running"}] = run["sessionMesgs"]

    assert length(swim["lengthMesgs"]) == 14
    assert [%{"poolLength" => 25, "subSport" => "lapSwimming"}] = swim["sessionMesgs"]
    refute Map.has_key?(swim, "recordMesgs")
  end

  test "answers a corrupt file with an error and keeps serving" do
    pid = Decoder.os_pid()

    assert {:error, "integrity check failed" <> _} = Decoder.decode(fixture("corrupt.fit"))
    assert {:ok, _} = Decoder.decode(fixture("swim.fit"))
    assert Decoder.os_pid() == pid
  end

  test "answers bytes that are not a FIT file with an error" do
    assert {:error, "not a FIT file"} = Decoder.decode("a text file, not a recording")
  end

  @tag :capture_log
  test "starts a new Node process for the next request after one is killed" do
    server = start_decoder()
    old_pid = Decoder.os_pid(server)

    System.cmd("kill", ["-KILL", Integer.to_string(old_pid)])

    assert await_new_process(server, old_pid) == :restarted

    assert {:ok, %{messages: %{"sessionMesgs" => [_]}}} =
             Decoder.decode(fixture("swim.fit"), server: server)

    assert Decoder.os_pid(server) not in [nil, old_pid]
  end

  test "kills a request that runs past its timeout and serves the next one" do
    server = start_decoder()
    old_pid = Decoder.os_pid(server)

    assert {:error, :timeout} = Decoder.decode(fixture("ride.fit"), server: server, timeout: 0)
    assert {:ok, _} = Decoder.decode(fixture("swim.fit"), server: server)
    assert Decoder.os_pid(server) != old_pid
  end

  test "serves concurrent requests one at a time, each with its own answer" do
    names = ["ride.fit", "run.fit", "swim.fit", "corrupt.fit"]

    results =
      names
      |> Enum.map(fn name -> Task.async(fn -> Decoder.decode(fixture(name)) end) end)
      |> Task.await_many(10_000)

    assert [{:ok, ride}, {:ok, run}, {:ok, swim}, {:error, _}] = results
    assert [%{"sport" => "cycling"}] = ride.messages["sessionMesgs"]
    assert [%{"sport" => "running"}] = run.messages["sessionMesgs"]
    assert [%{"sport" => "swimming"}] = swim.messages["sessionMesgs"]
  end

  @tag :capture_log
  @tag :tmp_dir
  test "fails a request answered with something other than a response and restarts", %{
    tmp_dir: tmp_dir
  } do
    script = Path.join(tmp_dir, "garbles.js")

    File.write!(script, """
    process.stdin.on("data", () => {
      const body = Buffer.from("Warning: not a response");
      const length = Buffer.alloc(4);
      length.writeUInt32BE(body.length);
      process.stdout.write(Buffer.concat([length, body]));
    });
    """)

    server = start_decoder(script: script)
    old_pid = Decoder.os_pid(server)

    assert {:error, {:bad_response, "Warning: not a response"}} =
             Decoder.decode(fixture("swim.fit"), server: server)

    assert {:error, {:bad_response, _}} = Decoder.decode(fixture("swim.fit"), server: server)
    assert Decoder.os_pid(server) != old_pid
  end

  @tag :capture_log
  @tag :tmp_dir
  test "fails a request whose Node process exits while serving it", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "exits.js")
    File.write!(script, "process.stdin.once('data', () => process.exit(3));")
    server = start_decoder(script: script)

    assert {:error, {:decoder_exited, 3}} = Decoder.decode(fixture("swim.fit"), server: server)
    assert {:error, {:decoder_exited, 3}} = Decoder.decode(fixture("swim.fit"), server: server)
  end
end
