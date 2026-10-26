defmodule VireWeb.DayController do
  use VireWeb, :controller

  alias Vire.Activities
  alias Vire.Training

  def show(conn, %{"date" => date}) do
    case Date.from_iso8601(date) do
      {:ok, date} ->
        scope = conn.assigns.current_scope
        day = Training.get_day(scope, date)

        render(conn, :show,
          date: date,
          day: day,
          matched: matched_activities(scope, day),
          unmatched: Training.list_unmatched_activities(scope, date)
        )

      {:error, _reason} ->
        conn |> put_status(:bad_request) |> put_view(VireWeb.ErrorJSON) |> render(:"400")
    end
  end

  defp matched_activities(_scope, nil), do: %{}

  defp matched_activities(scope, day) do
    ids = for %{activity_id: id} <- day.sessions, id, do: id

    scope
    |> Activities.list_activities_by_id(ids)
    |> Map.new(&{&1.id, &1})
  end
end
