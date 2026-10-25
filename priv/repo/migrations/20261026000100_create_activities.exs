defmodule Vire.Repo.Migrations.CreateActivities do
  use Ecto.Migration

  def change do
    create table(:activities) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :source_file_id,
          references(:source_files, type: :uuid, with: [user_id: :user_id], on_delete: :nothing)

      add :provider, :provider
      add :external_id, :text
      add :started_at, :timestamptz, null: false
      add :utc_offset_seconds, :integer, null: false
      add :local_date, :date, null: false
      add :discipline, :discipline, null: false
      add :sport, :text
      add :sub_sport, :text
      add :duration_seconds, :integer, null: false
      add :distance_m, :numeric, precision: 9, scale: 1
      add :pool_length_m, :numeric, precision: 5, scale: 2
      add :training_load, :numeric, precision: 6, scale: 1
      add :provider_summary, :jsonb

      timestamps()
    end

    create unique_index(:activities, [:id, :user_id])
    create unique_index(:activities, [:source_file_id])
    create unique_index(:activities, [:user_id, :provider, :external_id])

    create constraint(:activities, :activities_provider_with_external_id,
             check: "(provider is null) = (external_id is null)"
           )

    create constraint(:activities, :activities_from_file_or_provider,
             check: "source_file_id is not null or provider is not null"
           )

    create index(:activities, [:user_id, "local_date desc"], name: :activities_user_local_date)

    create table(:activity_laps) do
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :lap_index, :smallint, null: false
      add :started_at, :timestamptz, null: false
      add :elapsed_seconds, :integer, null: false
      add :moving_seconds, :integer
      add :distance_m, :numeric, precision: 9, scale: 1
      add :avg_heart_rate, :smallint
      add :avg_power, :smallint
      add :avg_speed_mps, :numeric, precision: 6, scale: 3

      timestamps()
    end

    create unique_index(:activity_laps, [:activity_id, :lap_index])

    create table(:activity_lengths) do
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all), null: false
      add :length_index, :smallint, null: false
      add :lap_index, :smallint, null: false
      add :started_at, :timestamptz, null: false
      add :elapsed_seconds, :numeric, precision: 7, scale: 2, null: false
      add :active, :boolean, null: false
      add :stroke, :text
      add :strokes, :smallint

      timestamps()
    end

    create unique_index(:activity_lengths, [:activity_id, :length_index])

    create table(:activity_streams, primary_key: false) do
      add :activity_id, references(:activities, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :channel, :text, null: false, primary_key: true
      add :unit, :text, null: false
      add :samples, {:array, :float}, null: false

      timestamps()
    end

    alter table(:training_sessions) do
      modify :activity_id,
             references(:activities,
               type: :uuid,
               with: [user_id: :user_id],
               on_delete: {:nilify, [:activity_id]}
             ),
             from: :uuid
    end
  end
end
