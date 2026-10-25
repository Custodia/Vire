defmodule VireWeb.HealthControllerTest do
  use VireWeb.ConnCase, async: true

  test "reports the application as up once its database answers", %{conn: conn} do
    conn = get(conn, ~p"/api/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
