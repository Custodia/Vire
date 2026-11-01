defmodule Vire.Activities.Activity do
  @moduledoc false

  use Vire.Schema

  import Ecto.Changeset

  @disciplines [:swim, :bike, :run, :strength, :other]
  @from_file [
    :started_at,
    :utc_offset_seconds,
    :local_date,
    :discipline,
    :sport,
    :sub_sport,
    :duration_seconds,
    :distance_m,
    :pool_length_m
  ]

  @from_provider [:provider, :external_id, :training_load, :provider_summary]
  @summarised [
    :started_at,
    :utc_offset_seconds,
    :local_date,
    :discipline,
    :duration_seconds,
    :distance_m
  ]

  schema "activities" do
    field :provider, Ecto.Enum, values: [:garmin]
    field :external_id, :string
    field :started_at, :utc_datetime_usec
    field :utc_offset_seconds, :integer
    field :local_date, :date
    field :discipline, Ecto.Enum, values: @disciplines
    field :sport, :string
    field :sub_sport, :string
    field :duration_seconds, :integer
    field :distance_m, Vire.Numeric
    field :pool_length_m, Vire.Numeric
    field :training_load, Vire.Numeric
    field :provider_summary, :map

    belongs_to :user, Vire.Accounts.User
    belongs_to :source_file, Vire.Ingest.SourceFile

    has_many :laps, Vire.Activities.Lap
    has_many :lengths, Vire.Activities.Length
    has_many :streams, Vire.Activities.ActivityStream

    timestamps()
  end

  @doc "The fields a parsed file sets, and replaces when the file is parsed again."
  def from_file_fields, do: @from_file

  @doc "The fields only a provider sets."
  def from_provider_fields, do: @from_provider

  @doc """
  A changeset for what a provider's summary says. The summary's start,
  discipline, duration and distance are taken only while no source file backs
  the activity, since the file records them first-hand.
  """
  def provider_changeset(%__MODULE__{source_file_id: nil} = activity, attrs) do
    activity
    |> cast(attrs, @from_provider ++ @summarised)
    |> validate_required([:provider, :external_id | @summarised])
    |> validate_provider()
  end

  def provider_changeset(activity, attrs) do
    activity
    |> cast(attrs, @from_provider)
    |> validate_required([:provider, :external_id])
    |> validate_provider()
  end

  @doc "A changeset attaching the source file an activity was recorded in."
  def source_file_changeset(activity, source_file_id) do
    activity
    |> change(source_file_id: source_file_id)
    |> unique_constraint(:source_file_id)
    |> foreign_key_constraint(:source_file_id, name: :activities_source_file_id_fkey)
  end

  defp validate_provider(changeset) do
    changeset
    |> validate_number(:duration_seconds, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :provider, :external_id])
  end

  @doc "A changeset for the fields read from a source file."
  def file_changeset(activity, attrs) do
    activity
    |> cast(attrs, @from_file)
    |> validate_required([
      :started_at,
      :utc_offset_seconds,
      :local_date,
      :discipline,
      :duration_seconds
    ])
    |> validate_number(:duration_seconds, greater_than_or_equal_to: 0)
    |> unique_constraint(:source_file_id)
    |> foreign_key_constraint(:source_file_id, name: :activities_source_file_id_fkey)
  end
end
