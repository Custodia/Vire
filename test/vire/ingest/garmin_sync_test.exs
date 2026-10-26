defmodule Vire.Ingest.GarminSyncTest do
  use Vire.DataCase, async: true
  use Oban.Testing, repo: Vire.Repo

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Vire.Accounts
  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.Scope
  alias Vire.Activities.Activity
  alias Vire.Activities.ActivityStream
  alias Vire.Activities.Lap
  alias Vire.Ingest
  alias Vire.Ingest.DownloadWorker
  alias Vire.Ingest.Garmin
  alias Vire.Ingest.Garmin.TokenCache
  alias Vire.Ingest.GarminSync
  alias Vire.Ingest.SourceFile
  alias Vire.Ingest.SyncScheduler
  alias Vire.Ingest.SyncWorker

  @token_path "/personalapitoken-service/personal-api/personal-api-key/token"
  @search_path "/activitylist-service/activities/search/activities"
  @download_prefix "/download-service/files/activity/"

  @ride_start ~U[2026-07-15 02:00:00Z]
  @run_start ~U[2026-07-16 05:45:00Z]

  setup do
    user = user_fixture()
    scope = Scope.for_user(user)
    season_fixture(scope, %{name: "Summer", period: period(~D[2026-07-01], ~D[2026-07-31])})
    connection = provider_connection_fixture(user)
    %{scope: scope, user: user, connection: connection}
  end

  defp jwt do
    claims = Base.url_encode64(~s({"exp":#{System.os_time(:second) + 86_400}}), padding: false)
    "eyJhbGciOiJub25lIn0." <> claims <> ".c2ln"
  end

  defp summary(id, start, offset, type_key, extra \\ %{}) do
    Map.merge(
      %{
        "activityId" => id,
        "activityName" => "Invented #{type_key} #{id}",
        "startTimeGMT" => Calendar.strftime(start, "%Y-%m-%d %H:%M:%S"),
        "startTimeLocal" => Calendar.strftime(DateTime.add(start, offset), "%Y-%m-%d %H:%M:%S"),
        "activityType" => %{"typeId" => 10, "typeKey" => type_key, "parentTypeId" => 17},
        "duration" => 545.4,
        "elapsedDuration" => 600.0,
        "distance" => 4612.37,
        "activityTrainingLoad" => 61.37,
        "manualActivity" => false
      },
      extra
    )
  end

  defp ride_summary(id \\ 7_000_001, extra \\ %{}),
    do: summary(id, @ride_start, -7 * 3600, "road_biking", extra)

  defp run_summary(id \\ 7_000_002), do: summary(id, @run_start, 3 * 3600, "running")

  defp zip(fit) do
    {:ok, {_name, archive}} = :zip.create(~c"activity.zip", [{~c"activity.fit", fit}], [:memory])
    archive
  end

  defp stub_garmin(summaries, files \\ %{}, opts \\ []) do
    test = self()
    failing = Keyword.get(opts, :failing_searches, [])

    Req.Test.stub(Garmin, fn
      %{request_path: @token_path} = conn ->
        send(test, :token)
        Req.Test.text(conn, jwt())

      %{request_path: @search_path} = conn ->
        %{"startDate" => first, "endDate" => last, "start" => start, "limit" => limit} =
          Plug.Conn.fetch_query_params(conn).query_params

        send(test, {:search, first, last, String.to_integer(start)})

        if first in failing do
          Plug.Conn.send_resp(conn, 500, "")
        else
          page =
            summaries
            |> Enum.filter(&on_dates?(&1, first, last))
            |> Enum.drop(String.to_integer(start))
            |> Enum.take(String.to_integer(limit))

          Req.Test.json(conn, page)
        end

      %{request_path: @download_prefix <> id} = conn ->
        send(test, {:download, id})

        case files do
          %{^id => {:raw, body}} -> Plug.Conn.send_resp(conn, 200, body)
          %{^id => fit} -> Plug.Conn.send_resp(conn, 200, zip(fit))
          _no_file -> Plug.Conn.send_resp(conn, 404, "")
        end
    end)
  end

  defp on_dates?(summary, first, last) do
    date = String.slice(summary["startTimeLocal"], 0, 10)
    date >= first and date <= last
  end

  defp searches do
    receive do
      {:search, first, last, start} -> [{first, last, start} | searches()]
    after
      0 -> []
    end
  end

  defp sync(user, period \\ nil) do
    {:ok, _job} = Ingest.enqueue_sync(Scope.for_user(user), period)
    Oban.drain_queue(queue: :garmin)
  end

  defp sync_and_fetch(user) do
    {:ok, _job} = Ingest.enqueue_sync(Scope.for_user(user))
    garmin = Oban.drain_queue(queue: :garmin, with_scheduled: true, with_recursion: true)
    ingest = Oban.drain_queue(queue: :ingest)
    {garmin, ingest}
  end

  defp activities, do: Activity |> order_by(:started_at) |> Repo.all()

  defp connection(user), do: Accounts.get_provider_connection(Scope.for_user(user), :garmin)

  describe "discovery" do
    test "searches each season up to its last day", %{user: user, scope: scope} do
      season_fixture(scope, %{name: "Winter", period: period(~D[2026-01-05], ~D[2026-02-15])})
      stub_garmin([])

      assert %{success: 1} = sync(user)

      assert Enum.sort(searches()) == [
               {"2026-01-05", "2026-02-15", 0},
               {"2026-07-01", "2026-07-31", 0}
             ]
    end

    test "searches a season that runs on only up to the day after today", context do
      %{user: user, scope: scope} = context
      today = Date.utc_today()
      period = period(Date.add(today, -3), Date.add(today, 60))
      season_fixture(scope, %{name: "Current", period: period})
      stub_garmin([])

      assert %{success: 1} = sync(user, period)

      assert searches() == [
               {Date.to_iso8601(Date.add(today, -3)), Date.to_iso8601(Date.add(today, 1)), 0}
             ]
    end

    test "never fetches an activity outside every season", %{user: user} do
      june = summary(7_000_009, ~U[2026-06-20 06:00:00Z], 0, "running")
      stub_garmin([june, ride_summary(), run_summary()])

      assert %{success: 1} = sync(user)

      assert Enum.map(activities(), & &1.external_id) == ["7000001", "7000002"]
      assert searches() == [{"2026-07-01", "2026-07-31", 0}]
      assert length(all_enqueued(worker: DownloadWorker)) == 2
    end

    test "within a date range searches only the seasons' dates inside it", context do
      season_fixture(context.scope, %{
        name: "Winter",
        period: period(~D[2026-01-05], ~D[2026-02-15])
      })

      stub_garmin([ride_summary(), run_summary()])

      assert :ok =
               perform_job(SyncWorker, %{
                 user_id: context.user.id,
                 first: "2026-07-16",
                 last: "2026-09-30"
               })

      assert searches() == [{"2026-07-16", "2026-07-31", 0}]
      assert Enum.map(activities(), & &1.external_id) == ["7000002"]
    end

    test "stores a summary as a Garmin activity on its local date", %{user: user} do
      stub_garmin([ride_summary()])

      assert %{success: 1} = sync(user)

      assert [activity] = activities()
      assert activity.provider == :garmin
      assert activity.external_id == "7000001"
      assert activity.started_at == ~U[2026-07-15 02:00:00.000000Z]
      assert activity.utc_offset_seconds == -7 * 3600
      assert activity.local_date == ~D[2026-07-14]
      assert activity.discipline == :bike
      assert activity.duration_seconds == 545
      assert activity.distance_m == 4612.4
      assert activity.training_load == 61.4
      assert activity.provider_summary == ride_summary()
      assert activity.source_file_id == nil
    end

    test "follows the pages of a season", %{user: user} do
      summaries =
        for n <- 1..100 do
          summary(8_000_000 + n, DateTime.add(~U[2026-07-02 06:00:00Z], n * 3600), 0, "running")
        end

      stub_garmin(summaries)

      assert %{success: 1} = sync(user)

      assert Enum.sort(searches()) == [
               {"2026-07-01", "2026-07-31", 0},
               {"2026-07-01", "2026-07-31", 99}
             ]

      assert length(activities()) == 100
    end

    test "stores each summary once across runs", %{user: user} do
      stub_garmin([ride_summary(), run_summary()])
      assert %{success: 1} = sync(user)
      first = activities()

      stub_garmin([ride_summary(7_000_001, %{"activityTrainingLoad" => 70.0}), run_summary()])
      assert %{success: 1} = sync(user)

      assert Enum.map(activities(), & &1.id) == Enum.map(first, & &1.id)
      assert [%{training_load: 70.0}, _run] = activities()
    end

    test "skips a summary without a UTC start", %{user: user} do
      stub_garmin([Map.delete(ride_summary(7_000_010), "startTimeGMT"), run_summary()])

      assert %{success: 1} = sync(user)

      assert Enum.map(activities(), & &1.external_id) == ["7000002"]
    end

    test "skips a summary it cannot store", %{user: user} do
      stub_garmin([ride_summary(7_000_001, %{"duration" => -5}), run_summary()])

      log = capture_log(fn -> assert %{success: 1} = sync(user) end)

      assert log =~ "Garmin activity 7000001 was not stored"
      assert Enum.map(activities(), & &1.external_id) == ["7000002"]
    end

    test "does not fetch the file of a manual activity", %{user: user} do
      stub_garmin([ride_summary(7_000_001, %{"manualActivity" => true})])

      assert %{success: 1} = sync(user)

      assert [%Activity{external_id: "7000001"}] = activities()
      refute_enqueued(worker: DownloadWorker)
    end

    test "queues the downloads a few seconds apart", %{user: user} do
      stub_garmin([ride_summary(), run_summary()])

      assert %{success: 1} = sync(user)

      [first, second] =
        [worker: DownloadWorker] |> all_enqueued() |> Enum.sort_by(& &1.scheduled_at, DateTime)

      assert DateTime.diff(second.scheduled_at, first.scheduled_at) in 4..6
    end

    test "records the sync on the connection", %{user: user} do
      stub_garmin([])

      assert %{success: 1} = sync(user)

      assert %ProviderConnection{last_synced_at: %DateTime{}, paused_at: nil} = connection(user)
    end
  end

  describe "an activity from an upload" do
    test "takes the summary of the same start when it was uploaded first", context do
      uploaded = activity_fixture(context.scope, "ride.fit")
      stub_garmin([summary(7_000_001, DateTime.add(@ride_start, 40), -7 * 3600, "road_biking")])

      assert %{success: 1} = sync(context.user)

      assert [activity] = activities()
      assert activity.id == uploaded.id
      assert activity.provider == :garmin
      assert activity.external_id == "7000001"
      assert activity.training_load == 61.4
      assert activity.provider_summary["activityId"] == 7_000_001
      assert activity.source_file_id == uploaded.source_file_id
      assert activity.started_at == uploaded.started_at
      assert activity.duration_seconds == 540
      refute_enqueued(worker: DownloadWorker)
    end

    test "is kept apart from a summary more than a minute off", context do
      activity_fixture(context.scope, "ride.fit")
      stub_garmin([summary(7_000_001, DateTime.add(@ride_start, 61), -7 * 3600, "road_biking")])

      assert %{success: 1} = sync(context.user)

      assert [%Activity{provider: nil}, %Activity{provider: :garmin}] = activities()
    end

    test "attaches to the summary's activity when the file arrives after it", context do
      stub_garmin([ride_summary()])
      assert %{success: 1} = sync(context.user)
      [from_summary] = activities()

      {:stored, file} = Ingest.store_fit_file(context.scope, fit_fixture("ride.fit"), :upload)
      assert %{success: 1} = Oban.drain_queue(queue: :ingest)

      assert [activity] = activities()
      assert activity.id == from_summary.id
      assert activity.source_file_id == file.id
      assert activity.provider == :garmin
      assert activity.external_id == "7000001"
      assert activity.training_load == 61.4
      assert activity.provider_summary == ride_summary()
      assert activity.duration_seconds == 540
      assert activity.distance_m == 4590.0
      assert activity.sport == "cycling"
      assert Repo.aggregate(where(Lap, activity_id: ^activity.id), :count) == 2

      assert %{success: 1} = Oban.drain_queue(queue: :garmin, with_scheduled: true)
      refute_received {:download, _}
    end

    test "is merged with the summary's activity when Garmin's file is the upload", context do
      uploaded = activity_fixture(context.scope, "ride.fit")
      off = summary(7_000_001, DateTime.add(@ride_start, 300), -7 * 3600, "road_biking")
      stub_garmin([off], %{"7000001" => fit_fixture("ride.fit")})

      assert {%{success: 2}, %{success: 1}} = sync_and_fetch(context.user)

      assert [activity] = activities()
      assert activity.id == uploaded.id
      assert activity.external_id == "7000001"
      assert activity.provider_summary == off
      assert [%SourceFile{origin: :upload}] = Repo.all(SourceFile)
    end
  end

  describe "the download" do
    test "stores the file and parses it into the summary's activity", context do
      stub_garmin([ride_summary()], %{"7000001" => fit_fixture("ride.fit")})

      assert {%{success: 2}, %{success: 1}} = sync_and_fetch(context.user)

      assert_received {:download, "7000001"}
      assert [activity] = activities()

      assert %SourceFile{origin: :garmin_api, status: :processed} =
               Repo.get(SourceFile, activity.source_file_id)

      assert activity.provider == :garmin
      assert activity.external_id == "7000001"
      assert activity.training_load == 61.4
      assert activity.provider_summary == ride_summary()
      assert activity.duration_seconds == 540
      assert activity.sport == "cycling"
      assert activity.sub_sport == "road"
      assert Repo.aggregate(where(Lap, activity_id: ^activity.id), :count) == 2
      assert Repo.aggregate(where(ActivityStream, activity_id: ^activity.id), :count) == 6
    end

    test "keeps the file's fields when the summary comes again", context do
      stub_garmin([ride_summary()], %{"7000001" => fit_fixture("ride.fit")})
      sync_and_fetch(context.user)

      assert %{success: 1} = sync(context.user)

      assert [%Activity{duration_seconds: 540, distance_m: 4590.0}] = activities()
      refute_enqueued(worker: DownloadWorker)
    end

    test "is cancelled when Garmin has no file", context do
      stub_garmin([ride_summary()])

      assert {%{success: 1, cancelled: 1}, %{success: 0}} = sync_and_fetch(context.user)

      assert [%Activity{source_file_id: nil}] = activities()
    end

    test "is not queued again by a later sync once cancelled", context do
      stub_garmin([ride_summary()])
      assert {%{cancelled: 1}, _ingest} = sync_and_fetch(context.user)
      assert_received {:download, "7000001"}

      assert {%{success: 1, cancelled: 0}, _ingest} = sync_and_fetch(context.user)

      refute_received {:download, _}
      assert [%Activity{source_file_id: nil}] = activities()
    end

    test "is cancelled when Garmin's archive holds no .fit file", context do
      stub_garmin([ride_summary()], %{"7000001" => {:raw, "not a zip"}})

      assert {%{success: 1, cancelled: 1}, _ingest} = sync_and_fetch(context.user)

      assert [%Activity{source_file_id: nil}] = activities()
    end

    test "is cancelled for an activity that is gone", context do
      assert {:cancel, "the activity no longer exists"} =
               perform_job(DownloadWorker, %{
                 user_id: context.user.id,
                 activity_id: Ecto.UUID.generate()
               })
    end

    test "of an activity with a file asks Garmin for nothing", context do
      activity = activity_fixture(context.scope, "run.fit")

      assert :ok =
               perform_job(DownloadWorker, %{user_id: context.user.id, activity_id: activity.id})

      refute_received {:download, _}
    end

    test "pauses the connection when the key is refused", context do
      stub_garmin([ride_summary()])
      assert %{success: 1} = sync(context.user)
      Req.Test.stub(Garmin, &Plug.Conn.send_resp(&1, 401, ""))
      TokenCache.delete(context.connection)

      assert %{cancelled: 1} = Oban.drain_queue(queue: :garmin, with_scheduled: true)

      assert %ProviderConnection{paused_at: %DateTime{}} = connection(context.user)
    end

    test "is retried after a failure Garmin may recover from", context do
      stub_garmin([ride_summary()])
      assert %{success: 1} = sync(context.user)

      Req.Test.stub(Garmin, fn
        %{request_path: @token_path} = conn -> Req.Test.text(conn, jwt())
        conn -> Plug.Conn.send_resp(conn, 503, "")
      end)

      assert %{failure: 1} = Oban.drain_queue(queue: :garmin, with_scheduled: true)
      assert %ProviderConnection{paused_at: nil} = connection(context.user)
    end

    test "has one job per activity", context do
      stub_garmin([ride_summary()])
      assert %{success: 1} = sync(context.user)
      assert %{success: 1} = sync(context.user)

      assert [_one] = all_enqueued(worker: DownloadWorker)
    end
  end

  describe "a failing run" do
    test "pauses the connection when Garmin refuses the key", %{user: user} do
      Req.Test.stub(Garmin, &Plug.Conn.send_resp(&1, 401, ""))

      assert %{cancelled: 1} = sync(user)

      assert %ProviderConnection{paused_at: %DateTime{}, last_synced_at: nil} = connection(user)
      assert activities() == []
    end

    test "pauses the connection when every search fails", %{user: user} do
      stub_garmin([ride_summary()], %{}, failing_searches: ["2026-07-01"])

      assert %{cancelled: 1} = sync(user)

      assert %ProviderConnection{paused_at: %DateTime{}, last_synced_at: nil} = connection(user)
    end

    test "is tried again when only some searches fail", %{user: user, scope: scope} do
      season_fixture(scope, %{name: "Winter", period: period(~D[2026-01-05], ~D[2026-02-15])})
      stub_garmin([ride_summary()], %{}, failing_searches: ["2026-01-05"])

      assert %{failure: 1} = sync(user)

      assert %ProviderConnection{paused_at: nil, last_synced_at: nil} = connection(user)
      assert [%Activity{external_id: "7000001"}] = activities()
    end

    test "is cancelled without a user, a connection or with a paused one", context do
      assert {:cancel, "the user no longer exists"} =
               perform_job(SyncWorker, %{user_id: Ecto.UUID.generate()})

      assert {:cancel, "the user has no Garmin connection"} =
               perform_job(SyncWorker, %{user_id: user_fixture().id})

      Accounts.pause_provider_connection(context.scope, context.connection)

      assert {:cancel, "the Garmin connection is paused"} =
               perform_job(SyncWorker, %{user_id: context.user.id})
    end
  end

  describe "enqueuing" do
    test "keeps one waiting sync per user", %{user: user} do
      {:ok, first} = Ingest.enqueue_sync(Scope.for_user(user))
      {:ok, second} = Ingest.enqueue_sync(Scope.for_user(user))

      assert second.id == first.id
      assert [_one] = all_enqueued(worker: SyncWorker)
    end

    test "widens a waiting sync to cover a second range", %{user: user} do
      {:ok, job} =
        Ingest.enqueue_sync(Scope.for_user(user), period(~D[2026-07-10], ~D[2026-07-12]))

      {:ok, _} = Ingest.enqueue_sync(Scope.for_user(user), period(~D[2026-07-01], ~D[2026-07-05]))

      assert %{args: %{"first" => "2026-07-01", "last" => "2026-07-12"}} =
               Repo.get(Oban.Job, job.id)

      {:ok, _} = Ingest.enqueue_sync(Scope.for_user(user))
      assert %{args: %{"first" => nil, "last" => nil}} = Repo.get(Oban.Job, job.id)

      {:ok, _} = Ingest.enqueue_sync(Scope.for_user(user), period(~D[2026-07-01], ~D[2026-07-05]))
      assert %{args: %{"first" => nil, "last" => nil}} = Repo.get(Oban.Job, job.id)
    end

    test "refuses a user without a connection or with a paused one", context do
      assert Ingest.enqueue_sync(Scope.for_user(user_fixture())) == {:error, :not_connected}

      Accounts.pause_provider_connection(context.scope, context.connection)

      assert Ingest.enqueue_sync(context.scope) == {:error, :paused}
      refute_enqueued(worker: SyncWorker)
    end

    test "sync now enqueues the scope's sync and returns the job", %{scope: scope, user: user} do
      assert {:ok, %Oban.Job{args: %{"user_id" => user_id}}} = Ingest.sync_now(scope)
      assert user_id == user.id
      assert_enqueued(worker: SyncWorker, args: %{user_id: user.id, first: nil, last: nil})
    end

    test "the schedule skips a paused connection", context do
      paused = user_fixture()
      paused_connection = provider_connection_fixture(paused)
      Accounts.pause_provider_connection(Scope.for_user(paused), paused_connection)
      user_fixture()

      assert :ok = perform_job(SyncScheduler, %{})

      assert_enqueued(worker: SyncWorker, args: %{user_id: context.user.id})
      refute_enqueued(worker: SyncWorker, args: %{user_id: paused.id})
    end
  end

  test "the periods leave out a season entirely past a range", %{scope: scope} do
    assert GarminSync.periods(scope, period(~D[2026-08-01], ~D[2026-08-31]), ~D[2026-10-26]) == []

    assert GarminSync.periods(scope, nil, ~D[2026-07-20]) == [
             period(~D[2026-07-01], ~D[2026-07-21])
           ]

    assert GarminSync.periods(scope, nil, ~D[2026-07-30]) == [
             period(~D[2026-07-01], ~D[2026-07-31])
           ]
  end
end
