defmodule Vire.Ingest do
  @moduledoc """
  Files arriving from providers and uploads. Every file is kept byte for byte,
  once per user: a file whose SHA-256 the user already has is not stored
  again.

  Every function takes a scope first and touches only its user's files.
  """

  import Ecto.Query

  alias Vire.Accounts.Scope
  alias Vire.Ingest.SourceFile
  alias Vire.Repo

  @doc """
  Stores `content` for the scope's user as a file of `kind` from `origin`.

  Returns `{:stored, file}` for a new file, and `{:existing, file}` with the
  stored file as it stands when the user already has one with the same
  SHA-256.
  """
  def store_file(%Scope{user: user}, content, kind, origin) when is_binary(content) do
    sha256 = :crypto.hash(:sha256, content)

    case file_by_hash(user.id, sha256) do
      nil -> insert_file(user.id, content, sha256, kind, origin)
      file -> {:existing, file}
    end
  end

  @doc "The scope's file with `id`, without its content, or `nil`."
  def get_file(%Scope{user: user}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> SourceFile |> where(user_id: ^user.id) |> Repo.get(uuid)
      :error -> nil
    end
  end

  defp insert_file(user_id, content, sha256, kind, origin) do
    changeset =
      SourceFile.create_changeset(%SourceFile{user_id: user_id}, %{
        kind: kind,
        origin: origin,
        sha256: sha256,
        byte_size: byte_size(content),
        content: content
      })

    # A concurrent store of the same file wins the unique index; this one then
    # returns that file.
    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: [:user_id, :sha256]) do
      {:ok, %SourceFile{id: nil}} -> {:existing, file_by_hash(user_id, sha256)}
      {:ok, file} -> {:stored, file}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp file_by_hash(user_id, sha256),
    do: SourceFile |> where(user_id: ^user_id, sha256: ^sha256) |> Repo.one()
end
