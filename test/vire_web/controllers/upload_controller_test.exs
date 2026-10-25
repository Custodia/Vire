defmodule VireWeb.UploadControllerTest do
  use VireWeb.ConnCase, async: true
  use Oban.Testing, repo: Vire.Repo

  alias Vire.Ingest.{ParseWorker, SourceFile}

  @fixtures Path.expand("../../support/fixtures/fit", __DIR__)

  defp upload(conn, name, filename \\ nil) do
    path = Path.join(@fixtures, name)

    post(conn, ~p"/api/uploads", %{"file" => %Plug.Upload{path: path, filename: filename || name}})
  end

  test "answers 401 without a session", %{conn: conn} do
    assert json_response(upload(conn, "ride.fit"), 401)
    assert json_response(get(conn, ~p"/api/uploads/#{Ecto.UUID.generate()}"), 401)
  end

  test "stores a fixture, parses it and reports the activity", %{conn: conn} do
    conn = sign_in(conn, user_fixture())

    created = json_response(upload(conn, "ride.fit"), 201)
    assert %{"id" => id, "status" => "pending"} = created
    assert_enqueued(worker: ParseWorker, args: %{source_file_id: id})

    assert %{"status" => "pending", "activity_id" => nil} =
             json_response(get(conn, ~p"/api/uploads/#{id}"), 200)

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :ingest)

    assert %{
             "id" => ^id,
             "status" => "processed",
             "processor_version" => 1,
             "error" => nil,
             "activity_id" => activity_id
           } = json_response(get(conn, ~p"/api/uploads/#{id}"), 200)

    assert is_binary(activity_id)
  end

  test "reports a file the decoder rejects as failed", %{conn: conn} do
    conn = sign_in(conn, user_fixture())
    %{"id" => id} = json_response(upload(conn, "corrupt.fit"), 201)

    Oban.drain_queue(queue: :ingest)

    assert %{"status" => "failed", "error" => error, "activity_id" => nil} =
             json_response(get(conn, ~p"/api/uploads/#{id}"), 200)

    assert is_binary(error)
  end

  test "answers 200 with the existing file for a repeated upload", %{conn: conn} do
    conn = sign_in(conn, user_fixture())
    %{"id" => id} = json_response(upload(conn, "run.fit"), 201)
    Oban.drain_queue(queue: :ingest)

    assert %{"id" => ^id, "status" => "processed"} = json_response(upload(conn, "run.fit"), 200)
    refute_enqueued(worker: ParseWorker)
  end

  test "answers 422 without a file", %{conn: conn} do
    conn = sign_in(conn, user_fixture())

    assert %{"errors" => %{"detail" => _}} =
             json_response(post(conn, ~p"/api/uploads", %{}), 422)

    assert json_response(post(conn, ~p"/api/uploads", %{"file" => "text"}), 422)
  end

  test "answers 422 for a file that is not a FIT file", %{conn: conn} do
    conn = sign_in(conn, user_fixture())
    path = Path.join(System.tmp_dir!(), "vire-not-fit-#{System.unique_integer([:positive])}.fit")
    File.write!(path, "this is not a workout")
    on_exit(fn -> File.rm(path) end)

    conn = post(conn, ~p"/api/uploads", %{"file" => %Plug.Upload{path: path, filename: "x.fit"}})

    assert %{"errors" => %{"detail" => _}} = json_response(conn, 422)
    refute_enqueued(worker: ParseWorker)
  end

  test "answers 413 for a body over 20 MB and stores nothing", %{conn: conn} do
    conn = sign_in(conn, user_fixture())
    boundary = "vire-oversized"

    body =
      "--#{boundary}\r\n" <>
        ~s(content-disposition: form-data; name="file"; filename="big.fit"\r\n) <>
        "content-type: application/octet-stream\r\n\r\n" <>
        :binary.copy(<<0>>, 20_000_001) <> "\r\n--#{boundary}--\r\n"

    assert_error_sent 413, fn ->
      conn
      |> put_req_header("content-type", "multipart/form-data; boundary=#{boundary}")
      |> post(~p"/api/uploads", body)
    end

    assert Vire.Repo.aggregate(SourceFile, :count) == 0
    refute_enqueued(worker: ParseWorker)
  end

  test "answers 404 for another user's file and for unknown ids", %{conn: conn} do
    owner = sign_in(conn, user_fixture())
    %{"id" => id} = json_response(upload(owner, "swim.fit"), 201)

    other = sign_in(build_conn(), user_fixture())

    assert json_response(get(other, ~p"/api/uploads/#{id}"), 404)
    assert json_response(get(other, ~p"/api/uploads/not-a-uuid"), 404)
  end

  test "stores the same file once per user", %{conn: conn} do
    %{"id" => first} = json_response(upload(sign_in(conn, user_fixture()), "swim.fit"), 201)

    %{"id" => second} =
      json_response(upload(sign_in(build_conn(), user_fixture()), "swim.fit"), 201)

    assert first != second
  end
end
