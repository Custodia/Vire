defmodule VireWeb.SyncControllerTest do
  use VireWeb.ConnCase, async: true
  use Oban.Testing, repo: Vire.Repo

  alias Vire.Accounts
  alias Vire.Accounts.Scope
  alias Vire.Ingest
  alias Vire.Ingest.SyncWorker
  alias Vire.Repo

  test "answers 401 without a session", %{conn: conn} do
    assert json_response(get(conn, ~p"/api/sync"), 401)
    assert json_response(post(conn, ~p"/api/sync"), 401)
  end

  describe "GET /api/sync" do
    test "answers that there is no connection and no run", %{conn: conn} do
      conn = conn |> sign_in(user_fixture()) |> get(~p"/api/sync")

      assert json_response(conn, 200) == %{
               "connection" => "none",
               "last_synced_at" => nil,
               "run" => nil
             }
    end

    test "answers a paused connection with its last sync", %{conn: conn} do
      user = user_fixture()
      scope = Scope.for_user(user)
      connection = provider_connection_fixture(user)
      {:ok, connection} = Accounts.mark_provider_connection_synced(scope, connection)
      {:ok, _} = Accounts.pause_provider_connection(scope, connection)

      body = conn |> sign_in(user) |> get(~p"/api/sync") |> json_response(200)

      assert %{"connection" => "paused", "last_synced_at" => synced_at} = body
      assert synced_at == DateTime.to_iso8601(connection.last_synced_at)
    end

    test "answers the latest run", %{conn: conn} do
      user = user_fixture()
      provider_connection_fixture(user)
      {:ok, _first} = Ingest.sync_now(Scope.for_user(user))
      Repo.update_all(Oban.Job, set: [state: "completed"])
      {:ok, latest} = Ingest.sync_now(Scope.for_user(user))

      body = conn |> sign_in(user) |> get(~p"/api/sync") |> json_response(200)

      assert %{"connection" => "active", "run" => %{"id" => id, "state" => "queued"}} = body
      assert id == latest.id
    end
  end

  test "queues a sync and answers 202 with its queued run", %{conn: conn} do
    user = user_fixture()
    provider_connection_fixture(user)

    conn = conn |> sign_in(user) |> post(~p"/api/sync")

    assert %{
             "connection" => "active",
             "last_synced_at" => nil,
             "run" => %{
               "id" => run_id,
               "trigger" => "manual",
               "state" => "queued",
               "error" => nil,
               "started_at" => nil,
               "finished_at" => nil,
               "files" => %{"total" => 0, "fetched" => 0, "failed" => 0},
               "activities" => []
             }
           } = json_response(conn, 202)

    assert_enqueued(worker: SyncWorker, args: %{user_id: user.id, run_id: run_id})
  end

  test "a second request while a sync waits answers the same run", %{conn: conn} do
    user = user_fixture()
    provider_connection_fixture(user)
    conn = sign_in(conn, user)

    first = conn |> post(~p"/api/sync") |> json_response(202)
    second = conn |> post(~p"/api/sync") |> json_response(202)

    assert second["run"]["id"] == first["run"]["id"]
  end

  test "answers 409 without a Garmin connection", %{conn: conn} do
    conn = conn |> sign_in(user_fixture()) |> post(~p"/api/sync")

    assert %{"reason" => "not_connected", "errors" => %{"detail" => detail}} =
             json_response(conn, 409)

    assert detail =~ "No Garmin connection"
    refute_enqueued(worker: SyncWorker)
  end

  test "answers 409 when the connection is paused", %{conn: conn} do
    user = user_fixture()
    connection = provider_connection_fixture(user)
    {:ok, _} = Accounts.pause_provider_connection(Scope.for_user(user), connection)

    conn = conn |> sign_in(user) |> post(~p"/api/sync")

    assert %{"reason" => "paused"} = json_response(conn, 409)
    refute_enqueued(worker: SyncWorker)
  end
end
