defmodule Vire.ObanTest do
  use Vire.DataCase, async: true
  use Oban.Testing, repo: Vire.Repo

  defmodule NoopWorker do
    use Oban.Worker

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  test "stores an enqueued job in the database" do
    {:ok, job} = Oban.insert(NoopWorker.new(%{"n" => 1}))

    assert_enqueued(worker: NoopWorker, args: %{"n" => 1})
    assert %Oban.Job{state: "available"} = Repo.get!(Oban.Job, job.id)
  end

  test "outside tests, enqueues the Garmin syncs every three hours" do
    config = Config.Reader.read!("config/config.exs", env: :dev)
    plugins = config[:vire][Oban][:plugins]

    assert {Oban.Plugins.Cron, crontab: [{"0 */3 * * *", Vire.Ingest.SyncScheduler}]} in plugins
    assert config[:vire][Oban][:queues][:garmin] == 1
  end

  test "runs a stored job to completion" do
    {:ok, job} = Oban.insert(NoopWorker.new(%{"n" => 2}))

    assert %{success: 1} = Oban.drain_queue(queue: :default)
    assert %Oban.Job{state: "completed"} = Repo.get!(Oban.Job, job.id)
  end
end
