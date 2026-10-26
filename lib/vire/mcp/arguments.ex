defmodule Vire.Mcp.Arguments do
  @moduledoc """
  The JSON Schema pieces tool inputs are built from. Dates are ISO 8601
  strings, ids are UUID strings, and a period is an object of an inclusive
  `first` and `last` date.
  """

  @disciplines ["swim", "bike", "run", "strength", "other"]

  @doc "The disciplines a session or an activity may have."
  def disciplines, do: @disciplines

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
end
