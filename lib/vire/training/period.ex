defmodule Vire.Training.Period do
  @moduledoc """
  A bounded run of dates, from `first` to `last` inclusive.

  As an Ecto type it maps to a Postgres `daterange`, which stores the same
  dates as the half-open range `[first, last + 1)`. It casts from a period, a
  `Date.Range` with a step of one, or a map with `first` and `last` given as
  dates or ISO 8601 strings.
  """

  use Ecto.Type

  @derive Jason.Encoder
  @enforce_keys [:first, :last]
  defstruct [:first, :last]

  @type t :: %__MODULE__{first: Date.t(), last: Date.t()}

  @doc "The period from `first` to `last`, both included."
  def new(%Date{} = first, %Date{} = last), do: %__MODULE__{first: first, last: last}

  @impl true
  def type, do: :daterange

  @impl true
  def cast(%__MODULE__{first: %Date{} = first, last: %Date{} = last}), do: ordered(first, last)
  def cast(%Date.Range{first: first, last: last, step: 1}), do: ordered(first, last)

  def cast(%{} = map) when not is_struct(map) do
    with {:ok, first} <- date(map, :first),
         {:ok, last} <- date(map, :last) do
      ordered(first, last)
    end
  end

  def cast(_value), do: :error

  @impl true
  def dump(%__MODULE__{first: %Date{} = first, last: %Date{} = last}) do
    if Date.compare(last, first) == :lt do
      :error
    else
      {:ok,
       %Postgrex.Range{
         lower: first,
         upper: Date.add(last, 1),
         lower_inclusive: true,
         upper_inclusive: false
       }}
    end
  end

  def dump(_value), do: :error

  @impl true
  def load(%Postgrex.Range{lower: %Date{} = lower, upper: %Date{} = upper} = range) do
    first = if range.lower_inclusive, do: lower, else: Date.add(lower, 1)
    last = if range.upper_inclusive, do: upper, else: Date.add(upper, -1)
    {:ok, new(first, last)}
  end

  def load(_value), do: :error

  defp ordered(first, last) do
    if Date.compare(last, first) == :lt do
      {:error, message: "must not end before it starts"}
    else
      {:ok, new(first, last)}
    end
  end

  defp date(map, key) do
    with value when is_binary(value) <- Map.get(map, key, Map.get(map, Atom.to_string(key))),
         {:ok, date} <- Date.from_iso8601(value) do
      {:ok, date}
    else
      %Date{} = date -> {:ok, date}
      _other -> :error
    end
  end
end
