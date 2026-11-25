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
  @trim_tolerance 2
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

  @doc """
  Narrows a parsed activity to the span Garmin's `summary` of it covers, when
  that span starts later or ends earlier than the recording, as it does after
  a trim in Garmin Connect, which leaves the original file as it was.

  Laps, lengths and stream samples outside the span are dropped, and a lap
  across its edge is cut to it, with its distance and averages read from the
  streams inside it. The duration and distance are the summary's. A summary
  that covers the whole recording, or none, leaves the activity as it is.
  """
  def trim_to_summary(parsed, summary) do
    with {first, last} <- summary_span(summary),
         from = max(DateTime.diff(first, parsed.activity.started_at), 0),
         until = min(DateTime.diff(last, parsed.activity.started_at), recorded_seconds(parsed)),
         true <- until > from,
         true <- from > @trim_tolerance or until < recorded_seconds(parsed) - @trim_tolerance do
      cut(parsed, from, until, summary)
    else
      _covers_the_recording -> parsed
    end
  end

  @doc """
  The start and end of the recording Garmin's `summary` covers, in UTC, or
  `nil` for a summary without them.
  """
  def summary_span(%{"startTimeGMT" => start} = summary) do
    with %DateTime{} = first <- gmt(start),
         %DateTime{} = last <- gmt(summary["endTimeGMT"]) || elapsed_end(first, summary) do
      {first, last}
    end
  end

  def summary_span(_summary), do: nil

  defp elapsed_end(first, %{"elapsedDuration" => seconds}) when is_number(seconds),
    do: DateTime.add(first, round(seconds * 1000), :millisecond)

  defp elapsed_end(_first, _summary), do: nil

  defp gmt(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> naive |> DateTime.from_naive!("Etc/UTC") |> Map.put(:microsecond, {0, 6})
      {:error, _reason} -> nil
    end
  end

  defp gmt(_value), do: nil

  defp recorded_seconds(%{activity: activity, laps: laps, streams: streams}) do
    lap_ends =
      Enum.map(laps, &(DateTime.diff(&1.started_at, activity.started_at) + &1.elapsed_seconds))

    Enum.max(lap_ends ++ Enum.map(streams, &length(&1.samples)), fn -> 0 end)
  end

  defp cut(%{activity: activity} = parsed, from, until, summary) do
    started_at = DateTime.add(activity.started_at, from)
    streams = Map.new(parsed.streams, &{&1.channel, &1.samples})

    laps =
      parsed.laps
      |> Enum.map(&cut_lap(&1, activity.started_at, from, until, streams))
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index(&%{&1 | lap_index: &2})

    lap_starts = Enum.map(laps, & &1.started_at)

    lengths =
      parsed.lengths
      |> Enum.filter(fn length ->
        second = DateTime.diff(length.started_at, activity.started_at)
        second >= from and second < until
      end)
      |> Enum.with_index(&%{&1 | length_index: &2, lap_index: lap_of(&1.started_at, lap_starts)})

    %{
      activity: %{
        activity
        | started_at: started_at,
          local_date:
            started_at |> DateTime.add(activity.utc_offset_seconds) |> DateTime.to_date(),
          duration_seconds: round_to(summary["duration"], 0) || activity.duration_seconds,
          distance_m: round_to(summary["distance"], 1) || activity.distance_m
      },
      laps: laps,
      lengths: lengths,
      streams:
        Enum.map(parsed.streams, &%{&1 | samples: Enum.slice(&1.samples, from, until - from)})
    }
  end

  defp cut_lap(lap, activity_start, from, until, streams) do
    start = DateTime.diff(lap.started_at, activity_start)
    finish = start + lap.elapsed_seconds

    cond do
      finish <= from or start >= until -> nil
      start >= from and finish <= until -> lap
      true -> clip_lap(lap, activity_start, max(start, from), min(finish, until), streams)
    end
  end

  defp clip_lap(lap, activity_start, start, finish, streams) do
    elapsed = finish - start
    moving = share(lap.moving_seconds, elapsed, lap.elapsed_seconds)
    window = start..(finish - 1)//1
    distance = distance_within(streams["distance"], window) || lap.distance_m

    %{
      lap
      | started_at: DateTime.add(activity_start, start),
        elapsed_seconds: elapsed,
        moving_seconds: moving,
        distance_m: round_to(distance, 1),
        avg_heart_rate: round_to(mean_within(streams["heart_rate"], window), 0),
        avg_power: round_to(mean_within(streams["power"], window), 0),
        avg_speed_mps: speed(distance, moving)
    }
  end

  defp speed(distance, moving) when is_number(distance) and is_number(moving) and moving > 0,
    do: round_to(distance / moving, 3)

  defp speed(_distance, _moving), do: nil

  defp share(nil, _part, _whole), do: nil
  defp share(_seconds, part, 0), do: part
  defp share(seconds, part, whole), do: round(seconds * part / whole)

  defp distance_within(nil, _window), do: nil

  defp distance_within(samples, first..last//1) do
    before = samples |> Enum.take(first) |> Enum.reject(&is_nil/1) |> List.last(0)

    case samples |> Enum.slice(first..last//1) |> Enum.reject(&is_nil/1) |> List.last() do
      nil -> nil
      reached -> reached - before
    end
  end

  defp mean_within(nil, _window), do: nil

  defp mean_within(samples, window) do
    case samples |> Enum.slice(window) |> Enum.reject(&is_nil/1) do
      [] -> nil
      values -> Enum.sum(values) / length(values)
    end
  end

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
