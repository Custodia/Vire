defmodule Vire.Events do
  @moduledoc """
  Notices of changes to a user's data, published on the user's topic once the
  change is written, for whatever shows that data as it changes. A notice
  carries the changed row; readers that need more read it from its context.

  The events:

    * `{:sync_run, %Vire.Ingest.SyncRun{}}`: a Garmin sync was queued,
      started, found activities, fetched or gave up on a file, finished or
      failed.
    * `{:source_file, %Vire.Ingest.SourceFile{}}`: a source file was
      processed or failed. It carries no content.
  """

  alias Vire.Accounts.Scope

  @doc "Subscribes the calling process to the events of the scope's user."
  def subscribe(%Scope{user: user}), do: Phoenix.PubSub.subscribe(Vire.PubSub, topic(user.id))

  @doc "Publishes `event` to the subscribers of the user with `user_id`."
  def publish(user_id, event), do: Phoenix.PubSub.broadcast(Vire.PubSub, topic(user_id), event)

  defp topic(user_id), do: "user:#{user_id}"
end
