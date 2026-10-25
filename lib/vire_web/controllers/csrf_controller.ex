defmodule VireWeb.CSRFController do
  use VireWeb, :controller

  def show(conn, _params), do: json(conn, %{token: get_csrf_token()})
end
