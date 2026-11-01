defmodule VireWeb.ActivityController do
  use VireWeb, :controller

  alias Vire.Activities

  @step_error "step must be a whole number of seconds from 1"

  def show(conn, %{"id" => id}) do
    case Activities.get_activity(conn.assigns.current_scope, id) do
      nil -> not_found(conn)
      activity -> render(conn, :show, activity: activity)
    end
  end

  def streams(conn, %{"id" => id} = params) do
    with {:ok, step} <- read_step(params["step"]),
         streams when is_map(streams) <-
           Activities.get_activity_streams(
             conn.assigns.current_scope,
             id,
             read_channels(params["channels"]),
             step
           ) do
      render(conn, :streams, id: id, step: step, streams: streams)
    else
      nil ->
        not_found(conn)

      {:error, message} ->
        conn |> put_status(:bad_request) |> json(%{errors: %{detail: message}})
    end
  end

  defp read_step(step) when is_binary(step) do
    case Integer.parse(step) do
      {step, ""} when step > 0 -> {:ok, step}
      _other -> {:error, @step_error}
    end
  end

  defp read_step(_step), do: {:error, @step_error}

  defp read_channels(channels) when is_binary(channels) and channels != "",
    do: String.split(channels, ",", trim: true)

  defp read_channels(_channels), do: :all

  defp not_found(conn),
    do: conn |> put_status(:not_found) |> put_view(VireWeb.ErrorJSON) |> render(:"404")
end
