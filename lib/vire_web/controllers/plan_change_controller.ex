defmodule VireWeb.PlanChangeController do
  use VireWeb, :controller

  alias Vire.Training

  @limit 8

  def index(conn, _params) do
    render(conn, :index,
      changes: Training.list_recent_changes(conn.assigns.current_scope, @limit)
    )
  end
end
