defmodule Vire.Mcp.Arguments do
  @moduledoc """
  The JSON Schema pieces tool inputs are built from, and the readers that turn
  their JSON values into dates and periods. Dates are ISO 8601 strings, ids
  are UUID strings, and a period is an object of an inclusive `first` and
  `last` date.
  """

  alias Vire.Training.Period

  @doc "An object schema of `properties`, requiring the keys in `required`."
  def object(properties, required \\ []) do
    schema = %{type: "object", properties: properties, additionalProperties: false}
    if required == [], do: schema, else: Map.put(schema, :required, required)
  end

  def string(description), do: %{type: "string", description: description}

  def id(description), do: %{type: "string", format: "uuid", description: description}

  def date(description),
    do: %{type: "string", format: "date", description: description <> ", as YYYY-MM-DD"}

  def period(description) do
    %{
      type: "object",
      description: description <> ", from first to last date inclusive",
      properties: %{
        first: date("The first date"),
        last: date("The last date")
      },
      required: ["first", "last"],
      additionalProperties: false
    }
  end

  def enum(values, description), do: %{type: "string", enum: values, description: description}

  def integer(description, minimum),
    do: %{type: "integer", minimum: minimum, description: description}

  @doc "Reads an ISO 8601 date from `args` under `key`."
  def read_date(args, key) do
    with value when is_binary(value) <- args[key],
         {:ok, date} <- Date.from_iso8601(value) do
      {:ok, date}
    else
      _invalid -> {:error, "#{key} must be an ISO 8601 date such as 2026-11-02"}
    end
  end

  @doc "Reads a period from `args` under `key`."
  def read_period(args, key) do
    case Period.cast(args[key]) do
      {:ok, period} ->
        {:ok, period}

      {:error, message: message} ->
        {:error, "#{key} #{message}"}

      :error ->
        {:error, "#{key} must be an object with first and last dates such as 2026-11-02"}
    end
  end
end
