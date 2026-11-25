defmodule VireWeb.FileControllerTest do
  use VireWeb.ConnCase, async: true

  import Vire.ActivitiesFixtures

  alias Vire.Accounts.Scope
  alias Vire.Ingest

  setup do
    scope = Scope.for_user(user_fixture())
    %{scope: scope, source: source_file_fixture(scope, "ride.fit")}
  end

  defp path(url) do
    %URI{path: path, query: query} = URI.parse(url)
    path <> "?" <> query
  end

  defp tamper(url, key, value) do
    %URI{path: path, query: query} = URI.parse(url)
    path <> "?" <> (query |> URI.decode_query() |> Map.put(key, value) |> URI.encode_query())
  end

  test "a fresh URL serves the file's bytes as a .fit attachment",
       %{conn: conn, scope: scope, source: file} do
    {url, expires_at} = Ingest.signed_file_url(scope, file)

    assert url =~ ~r"\Ahttp://localhost:4002/files/#{file.id}\?"
    assert DateTime.diff(expires_at, DateTime.utc_now()) in 899..900

    conn = get(conn, path(url))

    assert response(conn, 200) == fit_fixture("ride.fit")
    assert get_resp_header(conn, "content-type") == ["application/vnd.ant.fit"]

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="#{file.id}.fit")
           ]
  end

  test "a file of another kind is served as bytes", %{conn: conn, scope: scope} do
    {:stored, file} = Ingest.store_file(scope, "PK workbook", :nutrition_export, :upload)
    {url, _expires_at} = Ingest.signed_file_url(scope, file)

    conn = get(conn, path(url))

    assert response(conn, 200) == "PK workbook"
    assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
  end

  test "an altered or missing part of the URL answers 404",
       %{conn: conn, scope: scope, source: file} do
    {url, expires_at} = Ingest.signed_file_url(scope, file)
    other_file = source_file_fixture(scope, "run.fit")
    later = expires_at |> DateTime.add(3600) |> DateTime.to_unix() |> to_string()

    paths = [
      tamper(url, "signature", "AAAA"),
      tamper(url, "user", Ecto.UUID.generate()),
      tamper(url, "user", "not-a-uuid"),
      tamper(url, "expires", later),
      tamper(url, "expires", "soon"),
      String.replace(path(url), file.id, other_file.id),
      String.replace(path(url), file.id, "not-a-uuid"),
      "/files/#{file.id}",
      "/files/#{file.id}?user=#{scope.user.id}&expires=#{later}"
    ]

    for path <- paths do
      assert json_response(get(conn, path), 404) == %{"errors" => %{"detail" => "Not Found"}}
    end
  end

  test "an expired URL answers 404", %{conn: conn, scope: scope, source: file} do
    {url, _expires_at} =
      Ingest.signed_file_url(scope, file, DateTime.add(DateTime.utc_now(), -901))

    assert json_response(get(conn, path(url)), 404)
  end

  test "a URL signed for another user does not reach the file", %{conn: conn, source: file} do
    other = Scope.for_user(user_fixture())
    other_file = source_file_fixture(other, "ride.fit")
    {url, _expires_at} = Ingest.signed_file_url(other, other_file)

    assert response(get(conn, path(url)), 200) == fit_fixture("ride.fit")
    assert json_response(get(conn, String.replace(path(url), other_file.id, file.id)), 404)
  end
end
