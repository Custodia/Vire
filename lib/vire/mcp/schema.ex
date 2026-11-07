defmodule Vire.Mcp.Schema do
  @moduledoc """
  Checks a tool's arguments against its input schema, answering every error
  with the path of the value it names, such as `ops[3].sessions[2].date`.

  It reads the part of JSON Schema the tools are written in: `type`, `enum`,
  `const`, `properties` with `required` and `additionalProperties: false`,
  `items`, `minItems`, `maxItems`, `minimum`, `maximum`, `minLength`, the
  `date` and `uuid` formats, `anyOf`, `oneOf`, and `$ref` to the root's
  `$defs`. A `oneOf` picks the branch whose `const` properties the value
  holds, so an error names the fields of the branch the value meant.
  """

  @type error :: %{path: String.t(), message: String.t()}

  @doc "Answers `:ok`, or `{:error, errors}` with every error found."
  @spec validate(map(), term()) :: :ok | {:error, [error()]}
  def validate(schema, value) do
    case check(schema, value, [], Map.get(schema, :"$defs", %{})) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp check(%{"$ref": "#/$defs/" <> name}, value, path, defs),
    do: check(Map.fetch!(defs, String.to_existing_atom(name)), value, path, defs)

  defp check(%{oneOf: branches}, value, path, defs),
    do: check_one_of(branches, value, path, defs)

  defp check(%{anyOf: branches}, value, path, defs),
    do: check_any_of(branches, value, path, defs)

  defp check(schema, value, path, defs) do
    case check_type(schema, value, path) do
      [] -> check_value(schema, value, path, defs)
      errors -> errors
    end
  end

  defp check_type(%{type: types}, value, path) do
    types = List.wrap(types)

    if Enum.any?(types, &type?(&1, value)),
      do: [],
      else: [error(path, "must be " <> Enum.map_join(types, " or ", &type_name/1))]
  end

  defp check_type(_schema, _value, _path), do: []

  defp check_value(_schema, nil, _path, _defs), do: []

  defp check_value(schema, value, path, defs) when is_map(value) do
    properties = Map.get(schema, :properties, %{})
    known = Map.new(properties, fn {key, property} -> {to_string(key), property} end)

    missing =
      for key <- Map.get(schema, :required, []),
          not Map.has_key?(value, key),
          do: error(path ++ [key], "is required")

    unknown =
      if Map.get(schema, :additionalProperties) == false,
        do: for(key <- Map.keys(value), not Map.has_key?(known, key), do: unknown(path, key)),
        else: []

    nested =
      for {key, item} <- value,
          property = known[key],
          property != nil,
          do: check(property, item, path ++ [key], defs)

    missing ++ unknown ++ List.flatten(nested)
  end

  defp check_value(schema, value, path, defs) when is_list(value) do
    size =
      cond do
        value |> length() |> below?(schema[:minItems]) ->
          [error(path, "must hold at least #{schema.minItems} items")]

        is_integer(schema[:maxItems]) and length(value) > schema.maxItems ->
          [error(path, "must hold at most #{schema.maxItems} items")]

        true ->
          []
      end

    items =
      case schema[:items] do
        nil ->
          []

        item_schema ->
          value
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, index} ->
            check(item_schema, item, path ++ [index], defs)
          end)
      end

    size ++ items
  end

  defp check_value(schema, value, path, _defs) do
    case Enum.find_value(
           [:const, :enum, :minimum, :maximum, :minLength, :format],
           &scalar(&1, schema, value)
         ) do
      nil -> []
      message -> [error(path, message)]
    end
  end

  defp scalar(:const, %{const: const}, value) when value != const, do: "must be #{inspect(const)}"

  defp scalar(:enum, %{enum: values}, value),
    do: if(value not in values, do: "must be one of " <> Enum.join(values, ", "))

  defp scalar(:minimum, %{minimum: minimum}, value) when is_number(value) and value < minimum,
    do: "must be at least #{minimum}"

  defp scalar(:maximum, %{maximum: maximum}, value) when is_number(value) and value > maximum,
    do: "must be at most #{maximum}"

  defp scalar(:minLength, %{minLength: length}, value) when is_binary(value),
    do: if(String.length(String.trim(value)) < length, do: "can't be blank")

  defp scalar(:format, %{format: format}, value),
    do: if(not format?(format, value), do: format_message(format))

  defp scalar(_check, _schema, _value), do: nil

  defp check_one_of(branches, value, path, defs) when is_map(value) do
    case Enum.filter(branches, &consts_match?(&1, value)) do
      [branch | _rest] -> check(branch, value, path, defs)
      [] -> [error(path, no_branch(branches))]
    end
  end

  defp check_one_of(_branches, _value, path, _defs), do: [error(path, "must be an object")]

  defp check_any_of(branches, value, path, defs) do
    results = Enum.map(branches, &check(&1, value, path, defs))

    if Enum.any?(results, &(&1 == [])) do
      []
    else
      branches
      |> Enum.zip(results)
      |> Enum.sort_by(fn {branch, errors} ->
        {not type_matches?(branch, value), length(errors)}
      end)
      |> hd()
      |> elem(1)
    end
  end

  defp consts_match?(branch, value) do
    branch
    |> consts()
    |> Enum.all?(fn {key, const} -> Map.get(value, key) == const end)
  end

  defp consts(branch) do
    for {key, %{const: const}} <- Enum.sort(Map.get(branch, :properties, %{}), :desc),
        do: {to_string(key), const}
  end

  defp no_branch([first | _rest] = branches) do
    keys = first |> consts() |> Enum.map_join(" and ", &elem(&1, 0))

    keys <>
      " must be one of " <>
      Enum.map_join(branches, ", ", fn branch ->
        branch |> consts() |> Enum.map_join(" ", &elem(&1, 1))
      end)
  end

  defp type_matches?(%{type: types}, value), do: Enum.any?(List.wrap(types), &type?(&1, value))
  defp type_matches?(_branch, _value), do: true

  defp type?("string", value), do: is_binary(value)
  defp type?("integer", value), do: is_integer(value)
  defp type?("number", value), do: is_number(value)
  defp type?("boolean", value), do: is_boolean(value)
  defp type?("object", value), do: is_map(value)
  defp type?("array", value), do: is_list(value)
  defp type?("null", value), do: is_nil(value)

  defp type_name("string"), do: "a string"
  defp type_name("integer"), do: "a whole number"
  defp type_name("number"), do: "a number"
  defp type_name("boolean"), do: "true or false"
  defp type_name("object"), do: "an object"
  defp type_name("array"), do: "a list"
  defp type_name("null"), do: "null"

  defp format?("date", value) when is_binary(value),
    do: match?({:ok, _}, Date.from_iso8601(value))

  defp format?("uuid", value) when is_binary(value), do: Ecto.UUID.cast(value) != :error
  defp format?(_format, _value), do: true

  defp format_message("date"), do: "must be a date such as 2026-11-02"
  defp format_message("uuid"), do: "must be a UUID"

  defp below?(value, minimum), do: is_number(minimum) and value < minimum

  defp unknown(path, key), do: error(path ++ [key], "is not a known field")

  defp error(path, message), do: %{path: format_path(path), message: message}

  @doc "Writes a path of keys and list indexes as `ops[3].sessions[2].date`."
  def format_path(path) do
    Enum.reduce(path, "", fn
      index, acc when is_integer(index) -> acc <> "[#{index}]"
      key, "" -> to_string(key)
      key, acc -> acc <> "." <> to_string(key)
    end)
  end
end
