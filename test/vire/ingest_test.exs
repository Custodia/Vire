defmodule Vire.IngestTest do
  use Vire.DataCase, async: true

  import Ecto.Query

  alias Vire.Accounts.Scope
  alias Vire.Ingest
  alias Vire.Ingest.SourceFile

  setup do
    %{scope: Scope.for_user(user_fixture())}
  end

  describe "store_file/4" do
    test "stores the bytes with their SHA-256 and size as a pending file", %{scope: scope} do
      content = "first file"

      assert {:stored, file} = Ingest.store_file(scope, content, :fit, :upload)

      stored =
        Repo.one!(from f in SourceFile, where: f.id == ^file.id, select: {f, f.content})

      assert {%SourceFile{} = row, ^content} = stored
      assert row.user_id == scope.user.id
      assert row.kind == :fit
      assert row.origin == :upload
      assert row.sha256 == :crypto.hash(:sha256, content)
      assert row.byte_size == byte_size(content)
      assert row.status == :pending
      assert row.processor_version == nil
      assert row.error == nil
    end

    test "keeps the bytes out of the file's inspection", %{scope: scope} do
      {:stored, file} = Ingest.store_file(scope, "secret workout bytes", :fit, :upload)

      refute inspect(file) =~ "secret workout bytes"
    end

    test "returns the file the user already has by hash as it stands", %{scope: scope} do
      {:stored, first} = Ingest.store_file(scope, "same bytes", :fit, :garmin_api)

      assert {:existing, existing} = Ingest.store_file(scope, "same bytes", :fit, :upload)

      assert existing.id == first.id
      assert existing.origin == :garmin_api
      assert Repo.aggregate(SourceFile, :count) == 1
    end

    test "stores the same bytes once for each user", %{scope: scope} do
      other = Scope.for_user(user_fixture())

      {:stored, mine} = Ingest.store_file(scope, "shared bytes", :fit, :upload)
      {:stored, theirs} = Ingest.store_file(other, "shared bytes", :fit, :upload)

      assert mine.id != theirs.id
      assert mine.sha256 == theirs.sha256
      assert theirs.user_id == other.user.id
    end

    test "rejects an unknown kind or origin", %{scope: scope} do
      assert {:error, changeset} = Ingest.store_file(scope, "bytes", :gpx, :email)

      assert %{kind: ["is invalid"], origin: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "get_file/2" do
    test "reads the scope's file without its content", %{scope: scope} do
      {:stored, file} = Ingest.store_file(scope, "readable", :fit, :upload)

      read = Ingest.get_file(scope, file.id)

      assert read.id == file.id
      assert read.byte_size == 8
      assert %Ecto.Association.NotLoaded{} = read.user
      assert read.content == nil
    end

    test "reads another user's file as nil", %{scope: scope} do
      {:stored, file} = Ingest.store_file(scope, "private", :fit, :upload)

      assert Ingest.get_file(Scope.for_user(user_fixture()), file.id) == nil
    end

    test "reads an id that is not a UUID or not a file as nil", %{scope: scope} do
      assert Ingest.get_file(scope, "not-a-uuid") == nil
      assert Ingest.get_file(scope, Ecto.UUID.generate()) == nil
    end
  end

  describe "status constraints" do
    setup %{scope: scope} do
      {:stored, file} = Ingest.store_file(scope, "status", :fit, :upload)
      %{source_file: file}
    end

    test "a processed file carries its processor version", %{source_file: file} do
      assert {:error, changeset} =
               file |> SourceFile.status_changeset(%{status: :processed}) |> Repo.update()

      assert %{processor_version: ["must be present on a processed file"]} = errors_on(changeset)

      assert {:ok, %SourceFile{status: :processed, processor_version: 1}} =
               file
               |> SourceFile.status_changeset(%{status: :processed, processor_version: 1})
               |> Repo.update()
    end

    test "a failed file carries its error", %{source_file: file} do
      assert {:error, changeset} =
               file |> SourceFile.status_changeset(%{status: :failed}) |> Repo.update()

      assert %{error: ["must be present exactly when the file failed"]} = errors_on(changeset)

      assert {:ok, %SourceFile{status: :failed, error: "bad CRC"}} =
               file
               |> SourceFile.status_changeset(%{status: :failed, error: "bad CRC"})
               |> Repo.update()
    end

    test "a file that has not failed carries no error", %{source_file: file} do
      assert {:error, changeset} =
               file |> SourceFile.status_changeset(%{error: "stray"}) |> Repo.update()

      assert %{error: ["must be present exactly when the file failed"]} = errors_on(changeset)
    end

    test "a hash is 32 bytes", %{scope: scope} do
      assert {:error, changeset} =
               %SourceFile{user_id: scope.user.id}
               |> SourceFile.create_changeset(%{
                 kind: :fit,
                 origin: :upload,
                 sha256: <<1, 2, 3>>,
                 byte_size: 1,
                 content: "x"
               })
               |> Repo.insert()

      assert %{sha256: ["must be 32 bytes"]} = errors_on(changeset)
    end
  end
end
