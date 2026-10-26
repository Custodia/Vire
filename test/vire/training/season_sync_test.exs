defmodule Vire.Training.SeasonSyncTest do
  use Vire.DataCase, async: true
  use Oban.Testing, repo: Vire.Repo

  alias Vire.Accounts
  alias Vire.Accounts.Scope
  alias Vire.Ingest.SyncWorker
  alias Vire.Training

  setup do
    user = user_fixture()
    connection = provider_connection_fixture(user)
    scope = Scope.for_user(user)
    %{scope: scope, user: user, connection: connection}
  end

  defp create_season(scope, first, last) do
    {:ok, season} =
      Training.create_season(scope, %{
        name: "Summer",
        period: period(first, last),
        rationale: "Racing season"
      })

    season
  end

  defp update_season(scope, season, attrs) do
    Repo.delete_all(Oban.Job)
    {:ok, season} = Training.update_season(scope, season.id, attrs, "The plan changed")
    season
  end

  defp sync_args(user, first, last),
    do: %{user_id: user.id, first: Date.to_iso8601(first), last: Date.to_iso8601(last)}

  test "creating a season enqueues a sync of its dates", %{scope: scope, user: user} do
    create_season(scope, ~D[2026-07-01], ~D[2026-07-31])

    assert_enqueued(worker: SyncWorker, args: sync_args(user, ~D[2026-07-01], ~D[2026-07-31]))
  end

  test "a user without a Garmin connection or with a paused one gets no sync", context do
    create_season(scope_fixture(), ~D[2026-07-01], ~D[2026-07-31])
    Accounts.pause_provider_connection(context.scope, context.connection)
    create_season(context.scope, ~D[2026-07-01], ~D[2026-07-31])

    refute_enqueued(worker: SyncWorker)
  end

  test "a refused season enqueues nothing", %{scope: scope} do
    assert {:error, _changeset} = Training.create_season(scope, %{name: "No period"})

    refute_enqueued(worker: SyncWorker)
  end

  test "widening a season enqueues a sync of the dates it gained", %{scope: scope, user: user} do
    season = create_season(scope, ~D[2026-07-01], ~D[2026-07-31])

    season = update_season(scope, season, %{period: period(~D[2026-07-01], ~D[2026-08-15])})
    assert_enqueued(worker: SyncWorker, args: sync_args(user, ~D[2026-08-01], ~D[2026-08-15]))

    season = update_season(scope, season, %{period: period(~D[2026-06-20], ~D[2026-08-15])})
    assert_enqueued(worker: SyncWorker, args: sync_args(user, ~D[2026-06-20], ~D[2026-06-30]))

    update_season(scope, season, %{period: period(~D[2026-06-01], ~D[2026-09-30])})
    assert_enqueued(worker: SyncWorker, args: sync_args(user, ~D[2026-06-01], ~D[2026-09-30]))
  end

  test "moving a season enqueues a sync of its whole new period", %{scope: scope, user: user} do
    season = create_season(scope, ~D[2026-07-01], ~D[2026-07-31])

    update_season(scope, season, %{period: period(~D[2026-09-01], ~D[2026-09-30])})

    assert_enqueued(worker: SyncWorker, args: sync_args(user, ~D[2026-09-01], ~D[2026-09-30]))
  end

  test "narrowing or renaming a season enqueues nothing", %{scope: scope} do
    season = create_season(scope, ~D[2026-07-01], ~D[2026-07-31])

    season = update_season(scope, season, %{period: period(~D[2026-07-05], ~D[2026-07-25])})
    refute_enqueued(worker: SyncWorker)

    update_season(scope, season, %{name: "Late summer"})
    refute_enqueued(worker: SyncWorker)
  end
end
