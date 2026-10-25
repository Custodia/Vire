defmodule Vire.Ingest.SourceFile do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  schema "source_files" do
    field :kind, Ecto.Enum, values: [:fit, :nutrition_export]
    field :origin, Ecto.Enum, values: [:garmin_api, :upload, :mcp]
    field :sha256, :binary
    field :byte_size, :integer
    field :content, :binary, load_in_query: false, redact: true
    field :status, Ecto.Enum, values: [:pending, :processed, :failed], default: :pending
    field :processor_version, :integer
    field :error, :string

    belongs_to :user, Vire.Accounts.User

    timestamps()
  end

  @doc "A changeset for a new file from its kind, origin, content and the content's hash and size."
  def create_changeset(file, attrs) do
    file
    |> cast(attrs, [:kind, :origin, :sha256, :byte_size, :content])
    |> validate_required([:kind, :origin, :sha256, :byte_size, :content])
    |> assoc_constraint(:user)
    |> unique_constraint(:sha256, name: :source_files_user_id_sha256_index)
    |> check_constraint(:sha256, name: :source_files_sha256_length, message: "must be 32 bytes")
  end

  @doc """
  A changeset for the outcome of processing: `processed` carries the processor
  version and `failed` carries the error.
  """
  def status_changeset(file, attrs) do
    file
    |> cast(attrs, [:status, :processor_version, :error])
    |> validate_required([:status])
    |> check_constraint(:error,
      name: :source_files_failed_with_error,
      message: "must be present exactly when the file failed"
    )
    |> check_constraint(:processor_version,
      name: :source_files_processed_with_version,
      message: "must be present on a processed file"
    )
  end
end
