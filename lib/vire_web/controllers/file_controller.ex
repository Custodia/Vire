defmodule VireWeb.FileController do
  use VireWeb, :controller

  alias Vire.Ingest

  @types %{fit: {"application/vnd.ant.fit", ".fit"}}

  def show(conn, %{"id" => id} = params) do
    case Ingest.fetch_signed_file(id, params) do
      nil ->
        conn |> put_status(:not_found) |> json(%{errors: %{detail: "Not Found"}})

      file ->
        {content_type, extension} = Map.get(@types, file.kind, {"application/octet-stream", ""})

        conn
        |> put_resp_content_type(content_type, nil)
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="#{file.id}#{extension}")
        )
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(:ok, file.content)
    end
  end
end
