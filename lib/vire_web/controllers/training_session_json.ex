defmodule VireWeb.TrainingSessionJSON do
  alias VireWeb.TrainingJSON

  def show(%{session: session, activity: activity, previous: previous}) do
    session
    |> TrainingJSON.session_detail(activity)
    |> Map.put(:last_time, last_time(previous))
  end

  defp last_time(nil), do: nil

  defp last_time({session, activity}) do
    %{
      session_id: session.id,
      date: session.date,
      activity:
        activity
        |> TrainingJSON.activity_summary()
        |> Map.put(:avg_heart_rate, TrainingJSON.avg_heart_rate(activity.laps))
    }
  end
end
