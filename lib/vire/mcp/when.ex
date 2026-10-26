defmodule Vire.Mcp.When do
  @moduledoc """
  The dates a tool argument names, absolute or relative to today, the UTC
  date: a date; `today`, `yesterday` or `tomorrow`; `-3d` or `+2d`, days from
  today; `last-week`, `this-week` or `next-week`, Monday to Sunday;
  `last-month`, `this-month` or `next-month`; `last-cycle`, `this-cycle` or
  `next-cycle`; `this-block`, `this-phase` or `this-season`, the one holding
  today; or `{first, last}`, from the first date `first` names to the last
  date `last` names.
  """

  alias Vire.Accounts.Scope
  alias Vire.Training
  alias Vire.Training.Period

  @words ~w(today yesterday tomorrow last-week this-week next-week last-month this-month
            next-month last-cycle this-cycle next-cycle this-block this-phase this-season)

  @doc "The JSON Schema of a `when` argument, described by `description`."
  def schema(description) do
    word = %{
      type: "string",
      description:
        "A date as YYYY-MM-DD, -3d or +2d for days from today, or one of " <>
          Enum.join(@words, ", ")
    }

    %{
      anyOf: [
        word,
        %{
          type: "object",
          properties: %{first: word, last: word},
          required: ["first", "last"],
          additionalProperties: false
        }
      ],
      description:
        description <>
          ". Weeks run Monday to Sunday; this-block, this-phase and this-season hold " <>
          "today; last-cycle and next-cycle are the cycles before and after it. " <>
          "{first, last} runs from the first date of first to the last date of last. " <>
          "Today is the UTC date."
    }
  end

  @doc """
  The period `value` names for the scope's user on `today`, or
  `{:error, %{path, message}}` naming the part under `path` that names none.
  """
  @spec resolve(Scope.t(), term(), Date.t(), String.t()) ::
          {:ok, Period.t()} | {:error, %{path: String.t(), message: String.t()}}
  def resolve(scope, value, today \\ Date.utc_today(), path \\ "when")

  def resolve(scope, %{"first" => first, "last" => last}, today, path) do
    with {:ok, from} <- resolve(scope, first, today, path <> ".first"),
         {:ok, to} <- resolve(scope, last, today, path <> ".last") do
      if Date.before?(to.last, from.first),
        do:
          {:error,
           %{path: path, message: "ends on #{to.last}, before it starts on #{from.first}"}},
        else: {:ok, Period.new(from.first, to.last)}
    end
  end

  def resolve(scope, value, today, path) when is_binary(value) do
    case word(scope, value, today) do
      {:ok, %Period{} = period} -> {:ok, period}
      {:error, message} -> {:error, %{path: path, message: message}}
    end
  end

  def resolve(_scope, _value, _today, path),
    do: {:error, %{path: path, message: "must be a date, a relative date or {first, last}"}}

  defp word(_scope, "today", today), do: {:ok, day(today)}
  defp word(_scope, "yesterday", today), do: {:ok, day(Date.add(today, -1))}
  defp word(_scope, "tomorrow", today), do: {:ok, day(Date.add(today, 1))}
  defp word(_scope, "last-week", today), do: {:ok, week(Date.add(today, -7))}
  defp word(_scope, "this-week", today), do: {:ok, week(today)}
  defp word(_scope, "next-week", today), do: {:ok, week(Date.add(today, 7))}
  defp word(_scope, "last-month", today), do: {:ok, month(Date.shift(today, month: -1))}
  defp word(_scope, "this-month", today), do: {:ok, month(today)}
  defp word(_scope, "next-month", today), do: {:ok, month(Date.shift(today, month: 1))}
  defp word(scope, "last-cycle", today), do: neighbour(scope, :before, today)
  defp word(scope, "next-cycle", today), do: neighbour(scope, :after, today)
  defp word(scope, "this-cycle", today), do: holding(scope, :cycle, today)
  defp word(scope, "this-block", today), do: holding(scope, :block, today)
  defp word(scope, "this-phase", today), do: holding(scope, :phase, today)
  defp word(scope, "this-season", today), do: holding(scope, :season, today)

  defp word(_scope, value, today) do
    cond do
      match = Regex.run(~r/^([+-])(\d{1,4})d$/, value) ->
        [_, sign, days] = match
        days = String.to_integer(days)
        {:ok, day(Date.add(today, if(sign == "-", do: -days, else: days)))}

      match?({:ok, _date}, Date.from_iso8601(value)) ->
        {:ok, day(Date.from_iso8601!(value))}

      true ->
        {:error,
         "must be a date such as 2026-11-02, -3d, +2d or one of " <> Enum.join(@words, ", ")}
    end
  end

  defp day(date), do: Period.new(date, date)

  defp week(date) do
    monday = Date.beginning_of_week(date)
    Period.new(monday, Date.add(monday, 6))
  end

  defp month(date), do: Period.new(Date.beginning_of_month(date), Date.end_of_month(date))

  defp holding(scope, level, today) do
    case Enum.find(Training.list_periods(scope, level), &within?(today, &1)) do
      nil -> {:error, "no #{level} holds today, #{today}"}
      period -> {:ok, period}
    end
  end

  defp neighbour(scope, side, today) do
    periods = Training.list_periods(scope, :cycle)
    current = Enum.find(periods, &within?(today, &1))

    found =
      case side do
        :before ->
          periods
          |> Enum.filter(&Date.before?(&1.last, (current || day(today)).first))
          |> List.last()

        :after ->
          Enum.find(periods, &Date.after?(&1.first, (current || day(today)).last))
      end

    if found,
      do: {:ok, found},
      else: {:error, "no cycle comes #{side} the one holding #{today}"}
  end

  defp within?(date, %Period{first: first, last: last}),
    do: Date.compare(date, first) != :lt and Date.compare(date, last) != :gt
end
