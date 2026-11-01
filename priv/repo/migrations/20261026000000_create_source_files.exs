defmodule Vire.Repo.Migrations.CreateSourceFiles do
  use Ecto.Migration

  def change do
    execute "create type source_file_kind as enum ('fit', 'nutrition_export')",
            "drop type source_file_kind"

    execute "create type source_file_origin as enum ('garmin_api', 'upload', 'mcp')",
            "drop type source_file_origin"

    execute "create type source_file_status as enum ('pending', 'processed', 'failed')",
            "drop type source_file_status"

    create table(:source_files) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :kind, :source_file_kind, null: false
      add :origin, :source_file_origin, null: false
      add :sha256, :bytea, null: false
      add :byte_size, :integer, null: false
      add :content, :bytea, null: false
      add :status, :source_file_status, null: false, default: "pending"
      add :processor_version, :integer
      add :error, :text

      timestamps()
    end

    create unique_index(:source_files, [:user_id, :sha256])
    create unique_index(:source_files, [:id, :user_id])

    create constraint(:source_files, :source_files_sha256_length,
             check: "octet_length(sha256) = 32"
           )

    create constraint(:source_files, :source_files_failed_with_error,
             check: "(status = 'failed') = (error is not null)"
           )

    create constraint(:source_files, :source_files_processed_with_version,
             check: "status <> 'processed' or processor_version is not null"
           )
  end
end
