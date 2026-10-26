defmodule VireWeb.SyncControllerTest do
  use VireWeb.ConnCase, async: true
  use Oban.Testing, repo: Vire.Repo

  alias Vire.Accounts
  alias Vire.Accounts.Scope
  alias Vire.Ingest.SyncWorker

  test "answers 401 without a session", %{conn: conn} do
    assert json_response(post(conn, ~p"/api/sync"), 401)
  end

  test "queues a sync and answers 202 with the job id", %{conn: conn} do
    user = user_fixture()
    provider_connection_fixture(user)

    conn = conn |> sign_in(user) |> post(~p"/api/sync")

    assert %{"job_id" => job_id} = json_response(conn, 202)
    assert_enqueued(worker: SyncWorker, args: %{user_id: user.id})
    assert [%{id: ^job_id}] = all_enqueued(worker: SyncWorker)
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
