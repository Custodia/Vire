defmodule VireWeb.ActivityJSON do
  alias VireWeb.TrainingJSON

  def show(%{activity: activity}), do: TrainingJSON.activity_detail(activity)

  def streams(%{id: id, step: step, streams: streams}),
    do: %{activity_id: id, step: step, streams: streams}
end
