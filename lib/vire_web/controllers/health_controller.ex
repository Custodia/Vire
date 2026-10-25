defmodule VireWeb.HealthController do
  use VireWeb, :controller

  def show(conn, _params) do
    Vire.Repo.query!("select 1")
    json(conn, %{status: "ok"})
  end
end
