defmodule Vire.Ingest.GarminSync do
  @moduledoc """
  One user's Garmin sync: discovering the activities inside their seasons and
  fetching each one's original file.

  Discovery stores every summary as an activity and queues a download for each
  activity that has no file yet, a few seconds apart, on the `garmin` queue
  that sends Garmin one request at a time. A download stores the `.fit` file,
  attaches it to its activity and queues its parse.
  """

  require Logger

  alias Vire.Accounts
  alias Vire.Accounts.ProviderConnection
  alias Vire.Accounts.Scope
  alias Vire.Accounts.User
  alias Vire.Activities
  alias Vire.Activities.Activity
  alias Vire.Ingest
  alias Vire.Ingest.DownloadWorker
  alias Vire.Ingest.FitActivity
  alias Vire.Ingest.Garmin
  alias Vire.Repo
  alias Vire.Training
  alias Vire.Training.Period

  @download_spacing_seconds 5

  @doc """
  The scope of the user with `user_id` and their Garmin connection, or the
  cancellation of a job that has no user or no usable connection.
  """
  def connected(user_id) do
    with {:user, %User{} = user} <- {:user, Accounts.get_user(user_id)},
         scope = Scope.for_user(user),
         {:connection, %ProviderConnection{paused_at: nil} = connection} <-
           {:connection, Accounts.get_provider_connection(scope, :garmin)} do
      {:ok, scope, connection}
    else
      {:user, nil} -> {:cancel, "the user no longer exists"}
      {:connection, nil} -> {:cancel, "the user has no Garmin connection"}
      {:connection, _paused} -> {:cancel, "the Garmin connection is paused"}
    end
  end

  @doc """
  The dates a sync searches: each of the scope's seasons from its first day
  to the earlier of its last day and the day after `today`, the UTC date,
  within `range` when one is given.
  """
  def periods(%Scope{} = scope, range, %Date{} = today) do
    # Garmin filters on local start dates, which east of UTC run a day ahead.
    latest = Date.add(today, 1)

    scope
    |> Training.list_seasons()
    |> Enum.map(&within(&1.period, range, latest))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Searches Garmin for the dates `periods/3` gives and stores every summary
  found. After every search succeeds the connection records the sync.

  A key the token endpoint refuses, or a run in which every search fails,
  pauses the connection and answers `{:cancel, reason}`. A run in which only
  some searches fail answers `{:error, reason}`, so the job is tried again.
  """
  def run(%Scope{} = scope, %ProviderConnection{} = connection, range, %Date{} = today) do
    periods = periods(scope, range, today)
    results = search(scope, connection, periods)

    results
    |> Enum.flat_map(fn
      {:ok, activities} -> activities
      {:error, _reason} -> []
    end)
    |> enqueue_downloads(scope)

    errors = Enum.filter(results, &match?({:error, _}, &1))
    refused = Enum.find_value(errors, &refused_status/1)

    cond do
      errors == [] ->
        finish(scope, connection, periods)

      refused ->
        pause(scope, connection, "Garmin refused the API key with status #{refused}")

      length(errors) == length(results) ->
        pause(scope, connection, "every search failed: #{describe(errors)}")

      true ->
        {:error, "#{length(errors)} of #{length(results)} searches failed: #{describe(errors)}"}
    end
  end

  @doc """
  Downloads the original file of the scope's activity from Garmin, stores it,
  attaches it to the activity and queues its parse. An activity with a file
  already is left as it is.
  """
  def download(%Scope{} = scope, %ProviderConnection{} = connection, %Activity{} = activity) do
    case activity do
      %Activity{source_file_id: nil, provider: :garmin, external_id: external_id} ->
        scope
        |> Garmin.download_activity_file(connection, external_id)
        |> store_download(scope, connection, activity)

      %Activity{} ->
        :ok
    end
  end

  @doc """
  The attributes of an activity from a Garmin activity summary, or `nil` for
  a summary without an id or a start.
  """
  def summary_attrs(%{"activityId" => id} = summary) when is_integer(id) or is_binary(id) do
    with {:ok, utc} <- naive(summary["startTimeGMT"]),
         {:ok, local} <- naive(summary["startTimeLocal"]) do
      type_key = get_in(summary, ["activityType", "typeKey"])

      %{
        provider: :garmin,
        external_id: to_string(id),
        started_at: DateTime.from_naive!(utc, "Etc/UTC"),
        utc_offset_seconds: NaiveDateTime.diff(local, utc),
        local_date: NaiveDateTime.to_date(local),
        discipline: FitActivity.discipline(type_key, nil),
        duration_seconds: round(summary["duration"] || 0),
        distance_m: round_to(summary["distance"], 1),
        training_load: round_to(summary["activityTrainingLoad"], 1),
        provider_summary: summary
      }
    else
      _no_start -> nil
    end
  end

  def summary_attrs(_summary), do: nil

  defp within(%Period{first: first, last: last}, range, latest) do
    {first, last} =
      case range do
        nil -> {first, last}
        %Period{} -> {Enum.max([first, range.first], Date), Enum.min([last, range.last], Date)}
      end

    last = Enum.min([last, latest], Date)
    if Date.compare(first, last) != :gt, do: Period.new(first, last)
  end

  defp search(scope, connection, periods) do
    Enum.reduce_while(periods, [], fn period, results ->
      case Garmin.search_activities(scope, connection, period.first, period.last) do
        {:ok, summaries} -> {:cont, [{:ok, store_summaries(scope, summaries)} | results]}
        {:error, {:key_refused, _}} = refused -> {:halt, [refused | results]}
        {:error, reason} -> {:cont, [{:error, reason} | results]}
      end
    end)
    |> Enum.reverse()
  end

  defp store_summaries(scope, summaries) do
    for summary <- summaries,
        attrs = summary_attrs(summary),
        attrs != nil,
        {:ok, activity} <- [store_summary(scope, attrs)],
        is_nil(activity.source_file_id) and not manual?(summary),
        do: activity
  end

  defp store_summary(scope, attrs) do
    case Activities.upsert_provider_activity(scope, attrs) do
      {:ok, activity} ->
        Ingest.activity_recorded(scope, activity)
        {:ok, activity}

      {:error, changeset} ->
        Logger.warning(
          "Garmin activity #{attrs.external_id} was not stored: #{inspect(changeset.errors)}"
        )

        :error
    end
  end

  defp manual?(summary),
    do: summary["manualActivity"] == true or summary["isManualActivity"] == true

  defp enqueue_downloads(activities, scope) do
    activities
    |> Enum.uniq_by(& &1.id)
    |> Enum.with_index()
    |> Enum.each(fn {activity, index} ->
      %{user_id: scope.user.id, activity_id: activity.id}
      |> DownloadWorker.new(schedule_in: index * @download_spacing_seconds)
      |> Oban.insert!()
    end)
  end

  defp finish(scope, connection, _periods) do
    {:ok, _connection} = Accounts.mark_provider_connection_synced(scope, connection)
    :ok
  end

  defp pause(scope, connection, reason) do
    {:ok, _connection} = Accounts.pause_provider_connection(scope, connection)
    {:cancel, reason <> "; the Garmin connection is paused"}
  end

  defp store_download({:ok, fit}, scope, _connection, activity) do
    Repo.transact(fn ->
      with {stored, file} when stored in [:stored, :existing] <-
             Ingest.store_file(scope, fit, :fit, :garmin_api),
           {:ok, _activity} <- Activities.attach_source_file(scope, activity, file),
           {:ok, _job} <- Ingest.enqueue_parse(scope, file) do
        {:ok, file}
      end
    end)
    |> case do
      {:ok, _file} -> :ok
      {:error, :file_held_by_another_activity} -> {:cancel, "another activity holds the file"}
      {:error, :not_found} -> {:cancel, "the activity no longer exists"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp store_download({:error, {:key_refused, status}}, scope, connection, _activity),
    do: pause(scope, connection, "Garmin refused the API key with status #{status}")

  defp store_download({:error, {:status, 404}}, _scope, _connection, _activity),
    do: {:cancel, "Garmin has no file for the activity"}

  defp store_download({:error, :no_fit_file}, _scope, _connection, _activity),
    do: {:cancel, "Garmin's archive holds no .fit file"}

  defp store_download({:error, reason}, _scope, _connection, _activity), do: {:error, reason}

  defp refused_status({:error, {:key_refused, status}}), do: status
  defp refused_status({:error, _reason}), do: nil

  defp describe(errors),
    do: Enum.map_join(errors, ", ", fn {:error, reason} -> inspect(reason) end)

  defp naive(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> {:ok, NaiveDateTime.truncate(naive, :second)}
      {:error, _} -> :error
    end
  end

  defp naive(_value), do: :error

  defp round_to(nil, _places), do: nil
  defp round_to(value, places) when is_number(value), do: Float.round(value / 1, places)
end
