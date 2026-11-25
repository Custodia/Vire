defmodule VireWeb.ActivityJSON do
  alias VireWeb.TrainingJSON

  @doc "An activity's detail and the session it is matched to, or `nil`."
  def show(%{activity: activity, session: session}) do
    activity
    |> TrainingJSON.activity_detail()
    |> Map.put(
      :session,
      session &&
        %{
          id: session.id,
          title: TrainingJSON.title(session),
          planned_seconds: session.planned_seconds
        }
    )
  end

  def streams(%{id: id, step: step, streams: streams}),
    do: %{activity_id: id, step: step, streams: streams}
end
