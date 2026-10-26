defmodule Vire.Ingest.FitActivity do
  @moduledoc """
  Turns a decoded FIT activity file into an activity with its laps, lengths
  and streams.

  The activity starts at its first session's start, and its local date comes
  from the UTC offset the activity message records, as its local timestamp
  against its timestamp. Its duration is the timer time, which leaves pauses
  out. Each stream holds one sample per elapsed second from the start, `nil`
  where no record exists, so a pause shows as `nil`s.
  """

  @fit_epoch_unix 631_065_600
  @max_samples 7 * 24 * 3600
  @semicircles_per_degree 2 ** 31 / 180
  @position_channels ["position_lat", "position_long"]
  @disciplines %{
    "cycling" => :bike,
    "road_biking" => :bike,
    "gravel_cycling" => :bike,
    "mountain_biking" => :bike,
    "indoor_cycling" => :bike,
    "virtual_ride" => :bike,
    "running" => :run,
    "street_running" => :run,
    "trail_running" => :run,
    "track_running" => :run,
    "treadmill_running" => :run,
    "indoor_running" => :run,
    "swimming" => :swim,
    "lap_swimming" => :swim,
    "open_water_swimming" => :swim,
    "training" => :strength,
    "strength_training" => :strength
  }

  @type t :: %{activity: map(), laps: [map()], lengths: [map()], streams: [map()]}

  @spec from_decoded(%{messages: map(), units: map()}) :: {:ok, t()} | {:error, String.t()}
  def from_decoded(%{messages: messages, units: units}) do
    sessions = Map.get(messages, "sessionMesgs", [])
    records = Map.get(messages, "recordMesgs", [])
    session = List.first(sessions, %{})

    case started_at(session, records) do
      nil ->
        {:error, "the file has neither a session nor records with a start time"}

      started_at ->
        activity_message = messages |> Map.get("activityMesgs", []) |> List.first(%{})
        activity = activity(started_at, session, sessions, records, activity_message)
        laps = messages |> Map.get("lapMesgs", []) |> Enum.with_index(&lap(&1, &2, started_at))
        lengths = lengths(Map.get(messages, "lengthMesgs", []), laps, started_at)
        elapsed = sum(sessions, "totalElapsedTime")
        streams = streams(records, units, started_at, elapsed, activity.discipline)

        {:ok, %{activity: activity, laps: laps, lengths: lengths, streams: streams}}
    end
  end

  @doc """
  Vire's discipline for a sport and sub-sport, named as a FIT file records
  them or as Garmin's activity type keys do. The sport decides when the lookup
  knows it, then the sub-sport.
  """
  def discipline(sport, sub_sport),
    do: Map.get(@disciplines, sport) || Map.get(@disciplines, sub_sport, :other)

  defp activity(started_at, session, sessions, records, activity_message) do
    offset = utc_offset(activity_message)
    sport = profile_name(session["sport"])
    sub_sport = profile_name(session["subSport"])

    %{
      started_at: started_at,
      utc_offset_seconds: offset,
      local_date: started_at |> DateTime.add(offset) |> DateTime.to_date(),
      discipline: discipline(sport, sub_sport),
      sport: sport,
      sub_sport: sub_sport,
      duration_seconds: duration(sessions, activity_message, records, started_at),
      distance_m: sessions |> sum("totalDistance") |> round_to(1),
      pool_length_m: round_to(session["poolLength"], 2)
    }
  end

  defp started_at(session, records) do
    timestamp(session["startTime"]) ||
      Enum.find_value(records, &timestamp(&1["timestamp"]))
  end

  # A device writes the local timestamp from its own clock, a few seconds off
  # the UTC timestamp at times; offsets in use are whole quarter hours.
  defp utc_offset(%{"localTimestamp" => local, "timestamp" => utc}) when is_number(local) do
    case timestamp(utc) do
      nil ->
        0

      utc ->
        seconds = local - (DateTime.to_unix(utc) - @fit_epoch_unix)
        round(seconds / 900) * 900
    end
  end

  defp utc_offset(_activity_message), do: 0

  defp duration(sessions, activity_message, records, started_at) do
    seconds =
      sum(sessions, "totalTimerTime") || activity_message["totalTimerTime"] ||
        record_span(records, started_at)

    round(seconds)
  end

  defp record_span(records, started_at) do
    records
    |> Enum.map(&timestamp(&1["timestamp"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&DateTime.diff(&1, started_at))
    |> Enum.max(fn -> 0 end)
  end

  defp lap(lap, index, activity_start) do
    %{
      lap_index: index,
      started_at: start_of(lap, activity_start),
      elapsed_seconds: round(lap["totalElapsedTime"] || 0),
      moving_seconds: round_to(lap["totalMovingTime"] || lap["totalTimerTime"], 0),
      distance_m: round_to(lap["totalDistance"], 1),
      avg_heart_rate: lap["avgHeartRate"],
      avg_power: lap["avgPower"],
      avg_speed_mps: round_to(lap["enhancedAvgSpeed"] || lap["avgSpeed"], 3)
    }
  end

  defp lengths(lengths, laps, activity_start) do
    lap_starts = Enum.map(laps, & &1.started_at)

    lengths
    |> Enum.with_index()
    |> Enum.map(fn {length, index} ->
      started_at = start_of(length, activity_start)
      active = length["lengthType"] == "active"

      %{
        length_index: index,
        lap_index: lap_of(started_at, lap_starts),
        started_at: started_at,
        elapsed_seconds: round_to(length["totalElapsedTime"] || 0, 2),
        active: active,
        stroke: if(active, do: profile_name(length["swimStroke"])),
        strokes: length["totalStrokes"]
      }
    end)
  end

  defp start_of(message, activity_start) do
    timestamp(message["startTime"]) || timestamp(message["timestamp"]) || activity_start
  end

  # The last lap starting at or before the length.
  defp lap_of(started_at, lap_starts) do
    lap_starts
    |> Enum.with_index()
    |> Enum.filter(fn {lap_start, _index} -> DateTime.compare(lap_start, started_at) != :gt end)
    |> Enum.map(fn {_lap_start, index} -> index end)
    |> Enum.max(fn -> 0 end)
  end

  defp streams(records, units, started_at, elapsed, discipline) do
    sampled =
      for record <- records,
          at = timestamp(record["timestamp"]),
          second = div(DateTime.diff(at, started_at, :millisecond), 1000),
          second >= 0 and second < @max_samples,
          {channel, unit, value} <- samples(record, units, discipline),
          do: {channel, unit, second, value}

    length =
      sampled
      |> Enum.map(fn {_channel, _unit, second, _value} -> second + 1 end)
      |> Enum.max(fn -> 0 end)
      |> max(min(round(elapsed || 0), @max_samples))

    sampled
    |> Enum.group_by(fn {channel, unit, _second, _value} -> {channel, unit} end)
    |> Enum.map(fn {{channel, unit}, samples} ->
      values = Map.new(samples, fn {_channel, _unit, second, value} -> {second, value} end)
      %{channel: channel, unit: unit, samples: Enum.map(0..(length - 1)//1, &values[&1])}
    end)
    |> Enum.sort_by(& &1.channel)
  end

  # One record's values as {channel, unit, value}. Enhanced fields stand in for
  # the fields they extend, position is in degrees, and cadence carries its
  # fractional part; on runs it is in steps per minute, two per cycle.
  defp samples(record, units, discipline) do
    native_units = Map.get(units, "recordMesgs", %{})
    developer_units = Map.get(units, "developerFields", %{})

    native =
      record
      |> Map.drop(["timestamp", "developerFields"])
      |> Enum.filter(fn {_field, value} -> is_number(value) end)
      |> Map.new()
      |> enhanced()
      |> cadence(discipline)
      |> Enum.map(fn {field, value} ->
        channel(Macro.underscore(field), Map.get(native_units, field, ""), value)
      end)

    names = MapSet.new(native, fn {channel, _unit, _value} -> channel end)

    developer =
      for {field, value} <- Map.get(record, "developerFields", %{}),
          is_number(value),
          channel = developer_channel(field),
          channel not in names,
          do: {channel, Map.get(developer_units, field, ""), value / 1}

    native ++ developer
  end

  defp enhanced(fields) do
    Enum.reduce(fields, fields, fn
      {"enhanced" <> <<first::utf8, rest::binary>>, value}, fields ->
        base = String.downcase(<<first::utf8>>) <> rest

        fields
        |> Map.delete("enhanced" <> <<first::utf8, rest::binary>>)
        |> Map.put(base, value)

      _field, fields ->
        fields
    end)
  end

  defp cadence(%{"cadence" => cadence} = fields, discipline) do
    {fraction, fields} = Map.pop(fields, "fractionalCadence", 0)
    cycles = cadence + fraction

    case discipline do
      :run -> fields |> Map.delete("cadence") |> Map.put("stepCadence", cycles * 2)
      _other -> Map.put(fields, "cadence", cycles)
    end
  end

  defp cadence(fields, _discipline), do: fields

  defp channel("step_cadence", _unit, value), do: {"cadence", "spm", value / 1}

  defp channel(channel, _unit, value) when channel in @position_channels,
    do: {channel, "degrees", value / @semicircles_per_degree}

  defp channel(channel, unit, value), do: {channel, unit, value / 1}

  defp developer_channel(field) do
    case field |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_") do
      "" -> nil
      channel -> channel
    end
  end

  defp sum(messages, field) do
    case for(message <- messages, is_number(message[field]), do: message[field]) do
      [] -> nil
      values -> Enum.sum(values)
    end
  end

  defp timestamp(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _offset} ->
        {microseconds, _precision} = datetime.microsecond
        %{datetime | microsecond: {microseconds, 6}}

      {:error, _reason} ->
        nil
    end
  end

  defp timestamp(_value), do: nil

  defp profile_name(name) when is_binary(name), do: Macro.underscore(name)
  defp profile_name(_name), do: nil

  defp round_to(nil, _places), do: nil
  defp round_to(value, 0), do: round(value)
  defp round_to(value, places), do: Float.round(value / 1, places)
end
