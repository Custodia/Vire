defmodule VireWeb.DayController do
  use VireWeb, :controller

  alias Vire.Activities
  alias Vire.Training
  alias Vire.Training.Period

  @max_days 42

  def index(conn, params) do
    with {:ok, first} <- date_param(params, "from"),
         {:ok, last} <- date_param(params, "to"),
         days when days in 1..@max_days <- Date.diff(last, first) + 1 do
      scope = conn.assigns.current_scope
      period = Period.new(first, last)
      days = Training.list_days(scope, period)
      by_date = Map.new(days, &{&1.day, &1})

      unmatched =
        Enum.group_by(Training.list_unmatched_activities(scope, period), & &1.local_date)

      render(conn, :index,
        dates: Date.range(first, last),
        days: by_date,
        matched: matched_activities(scope, days),
        unmatched: unmatched
      )
    else
      _invalid -> bad_request(conn)
    end
  end

  def show(conn, %{"date" => date}) do
    case Date.from_iso8601(date) do
      {:ok, date} ->
        scope = conn.assigns.current_scope
        day = Training.get_day(scope, date)

        render(conn, :show,
          date: date,
          day: day,
          matched: matched_activities(scope, List.wrap(day)),
          unmatched: Training.list_unmatched_activities(scope, date)
        )

      {:error, _reason} ->
        bad_request(conn)
    end
  end

  defp date_param(params, key) do
    case params do
      %{^key => value} when is_binary(value) -> Date.from_iso8601(value)
      _missing -> :error
    end
  end

  defp bad_request(conn) do
    conn |> put_status(:bad_request) |> put_view(VireWeb.ErrorJSON) |> render(:"400")
  end

  defp matched_activities(scope, days) do
    ids = for %{sessions: sessions} <- days, %{activity_id: id} <- sessions, id, do: id

    scope
    |> Activities.list_activities_by_id(ids)
    |> Map.new(&{&1.id, &1})
  end
end
