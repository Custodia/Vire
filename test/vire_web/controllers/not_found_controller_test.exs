defmodule VireWeb.NotFoundControllerTest do
  use VireWeb.ConnCase, async: true

  test "answers an unknown API path with a JSON 404", %{conn: conn} do
    conn = get(conn, "/api/missing")

    assert json_response(conn, 404) == %{"errors" => %{"detail" => "Not Found"}}
  end

  test "answers every method under the API", %{conn: conn} do
    conn = post(conn, "/api/missing", %{})

    assert json_response(conn, 404) == %{"errors" => %{"detail" => "Not Found"}}
  end
end
