defmodule Vire.ActivitiesFixtures do
  alias Vire.Activities
  alias Vire.Ingest

  @fit Path.expand("fit", __DIR__)

  @doc "The bytes of a committed FIT fixture, such as `\"ride.fit\"`."
  def fit_fixture(name), do: File.read!(Path.join(@fit, name))

  @doc "Stores a FIT fixture as an upload for the scope's user."
  def source_file_fixture(scope, name) do
    {:stored, file} = Ingest.store_file(scope, fit_fixture(name), :fit, :upload)
    file
  end

  @doc "Stores a FIT fixture, parses it through the ingest queue, and returns its activity."
  def activity_fixture(scope, name) do
    file = source_file_fixture(scope, name)
    {:ok, _job} = Ingest.enqueue_parse(scope, file)
    %{success: 1} = Oban.drain_queue(queue: :ingest)
    Activities.get_activity_by_source_file(scope, file.id)
  end
end
