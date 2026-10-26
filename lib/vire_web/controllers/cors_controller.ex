defmodule VireWeb.CorsController do
  use VireWeb, :controller

  def preflight(conn, _params) do
    conn
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, mcp-protocol-version")
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(:no_content, "")
  end
end
