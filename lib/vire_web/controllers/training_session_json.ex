defmodule VireWeb.TrainingSessionJSON do
  alias VireWeb.TrainingJSON

  def show(%{session: session, activity: activity}),
    do: TrainingJSON.session_detail(session, activity)
end
