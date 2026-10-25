defmodule VireWeb.UploadController do
  use VireWeb, :controller

  alias Vire.Activities
  alias Vire.Ingest

  def create(conn, %{"file" => %Plug.Upload{path: path}}) do
    scope = conn.assigns.current_scope

    with {:ok, content} <- File.read(path),
         :ok <- check_fit(content) do
      store(conn, scope, content)
    else
      {:error, :not_fit} -> unprocessable(conn, "the file is not a FIT file")
      {:error, _reason} -> unprocessable(conn, "the file could not be read")
    end
  end

  def create(conn, _params), do: unprocessable(conn, "a file is required in the field file")

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    case Ingest.get_file(scope, id) do
      nil ->
        conn |> put_status(:not_found) |> put_view(VireWeb.ErrorJSON) |> render(:"404")

      file ->
        activity = Activities.get_activity_by_source_file(scope, file.id)
        render(conn, :show, file: file, activity: activity)
    end
  end

  defp store(conn, scope, content) do
    case Ingest.store_fit_file(scope, content, :upload) do
      {:stored, file} ->
        conn |> put_status(:created) |> render(:file, file: file)

      {:existing, file} ->
        render(conn, :file, file: file)

      {:error, _changeset} ->
        unprocessable(conn, "the file could not be stored")
    end
  end

  defp check_fit(<<_size, _protocol, _profile::binary-size(6), ".FIT", _::binary>>), do: :ok
  defp check_fit(_content), do: {:error, :not_fit}

  defp unprocessable(conn, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: message}})
  end
end
