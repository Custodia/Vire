defmodule VireWeb.DashboardControllerTest do
  use VireWeb.ConnCase, async: false

  @tag :tmp_dir
  test "answers that the dashboard is unavailable until it is built", %{
    conn: conn,
    tmp_dir: tmp_dir
  } do
    Application.put_env(:vire, :dashboard_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:vire, :dashboard_dir) end)

    conn = get(conn, ~p"/")

    assert response(conn, 503) =~ "not been built"
  end

  test "answers 404 for a missing file under /assets", %{conn: conn} do
    conn = get(conn, "/assets/missing-abc.js")

    assert response(conn, 404)
    assert response_content_type(conn, :txt)
  end

  test "answers 404 for a missing file outside /assets", %{conn: conn} do
    conn = get(conn, "/favicon.ico")

    assert response(conn, 404)
  end
end
