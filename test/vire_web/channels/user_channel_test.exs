defmodule VireWeb.UserChannelTest do
  use VireWeb.ChannelCase, async: true

  import Vire.ActivitiesFixtures
  import Vire.TrainingFixtures

  alias Vire.Accounts.Scope
  alias Vire.Events
  alias Vire.Ingest
  alias Vire.Ingest.SyncRun
  alias Vire.Repo
  alias VireWeb.UserChannel
  alias VireWeb.UserSocket

  # The channel reads the database before it pushes, which can take longer
  # than assert_push's default wait while the whole suite runs.
  @push_ms 1000

  setup do
    user = user_fixture()
    scope = Scope.for_user(user)
    %{user: user, scope: scope, socket: socket(UserSocket, "user_sockets:test", %{scope: scope})}
  end

  test "joins the user's own topic", %{socket: socket, user: user} do
    assert {:ok, %{}, _socket} = subscribe_and_join(socket, UserChannel, "user:#{user.id}")
  end

  test "refuses another user's topic", %{socket: socket} do
    assert subscribe_and_join(socket, UserChannel, "user:#{user_fixture().id}") ==
             {:error, %{reason: "unauthorized"}}
  end

  test "pushes the sync's state as its run changes", %{socket: socket, user: user, scope: scope} do
    provider_connection_fixture(user)
    {:ok, _socket} = join_own(socket, user)

    {:ok, run} = Ingest.sync_now(scope)

    run_id = run.id

    assert_push "sync",
                %{
                  connection: :active,
                  last_synced_at: nil,
                  run: %{id: ^run_id, trigger: :manual, state: :queued, activities: []}
                },
                @push_ms
  end

  test "lists the activities a run found with the sessions they are matched to", context do
    july = period(~D[2026-07-13], ~D[2026-07-19])
    season = season_fixture(context.scope, %{period: july})
    phase = phase_fixture(context.scope, season, %{period: july})
    block = block_fixture(context.scope, phase, %{period: july})
    cycle_fixture(context.scope, block, %{period: july})

    session =
      session_fixture(context.scope, %{
        date: ~D[2026-07-14],
        structure: %{"title" => "Saddle check ride"},
        planned_seconds: 600
      })

    activity = activity_fixture(context.scope, "ride.fit")

    run =
      Repo.insert!(%SyncRun{
        user_id: context.user.id,
        trigger: :manual,
        state: :finished,
        new_activity_ids: [activity.id]
      })

    {:ok, _socket} = join_own(context.socket, context.user)

    Events.publish(context.user.id, {:sync_run, run})

    assert_push "sync", %{run: %{state: :finished, activities: [pushed]}}, @push_ms
    assert pushed.id == activity.id
    assert pushed.local_date == ~D[2026-07-14]
    assert pushed.session == %{id: session.id, title: "Saddle check ride"}
  end

  test "pushes an upload's status once it is processed", context do
    {:ok, _socket} = join_own(context.socket, context.user)

    {:stored, file} = Ingest.store_fit_file(context.scope, fit_fixture("ride.fit"), :upload)
    %{success: 1} = Oban.drain_queue(queue: :ingest)

    file_id = file.id
    assert_push "upload", %{id: ^file_id, status: :processed, activity_id: activity_id}, @push_ms
    assert is_binary(activity_id)
  end

  defp join_own(socket, user) do
    {:ok, _reply, socket} = subscribe_and_join(socket, UserChannel, "user:#{user.id}")
    {:ok, socket}
  end
end
