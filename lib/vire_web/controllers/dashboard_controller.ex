defmodule VireWeb.DashboardController do
  use VireWeb, :controller

  def index(conn, %{"path" => path}) do
    index_path = Path.join(dashboard_dir(), "index.html")

    cond do
      file_path?(path) ->
        not_found(conn, %{})

      File.exists?(index_path) ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_content_type("text/html")
        |> send_file(200, index_path)

      true ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(503, "The dashboard has not been built.")
    end
  end

  def not_found(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not Found")
  end

  defp file_path?([]), do: false
  defp file_path?(path), do: path |> List.last() |> Path.extname() != ""

  defp dashboard_dir do
    Application.get_env(:vire, :dashboard_dir) || Application.app_dir(:vire, "priv/static")
  end
end
