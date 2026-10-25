defmodule VireWeb.DashboardControllerTest do
  use VireWeb.ConnCase, async: false

  describe "with the dashboard built" do
    @describetag :dashboard_build

    test "serves the dashboard page at the root", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert response(conn, 200) =~ ~s(<div id="root">)
      assert response_content_type(conn, :html)
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "serves the dashboard page at every path outside the API", %{conn: conn} do
      conn = get(conn, "/days/2026-03-14")

      assert response(conn, 200) =~ ~s(<div id="root">)
    end

    test "serves the files the page loads", %{conn: conn} do
      [script] = Regex.run(~r{/assets/[^"]+\.js}, get(conn, ~p"/") |> response(200))

      conn = get(build_conn(), script)

      assert response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    test "serves the web app manifest", %{conn: conn} do
      conn = get(conn, "/manifest.webmanifest")

      assert %{"start_url" => "/today"} = Jason.decode!(response(conn, 200))
    end
  end

  describe "without the dashboard built" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      Application.put_env(:vire, :dashboard_dir, tmp_dir)
      on_exit(fn -> Application.delete_env(:vire, :dashboard_dir) end)
    end

    test "answers that it is unavailable", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert response(conn, 503) =~ "not been built"
    end
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
