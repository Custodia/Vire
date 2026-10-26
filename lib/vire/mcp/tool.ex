defmodule Vire.Mcp.Tool do
  @moduledoc """
  One MCP tool: its name, the description an agent reads, the JSON Schema of
  its arguments, and the function that runs it.

  The function takes the request's scope and the arguments as a map with
  string keys. It answers `{:ok, map}`, which becomes the result's structured
  content and a text content holding the same JSON, or `{:error, reason}`,
  which becomes a result with `isError` and a text explaining the reason: a
  changeset's errors, `:not_found`, or a message.
  """

  alias Vire.Accounts.Scope

  @enforce_keys [:name, :description, :input_schema, :function]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          function: (Scope.t(), map() -> {:ok, map()} | {:error, term()})
        }

  @doc "The tool as `tools/list` describes it."
  def describe(%__MODULE__{} = tool),
    do: %{name: tool.name, description: tool.description, inputSchema: tool.input_schema}

  @doc """
  Runs the tool and answers its `tools/call` result. Arguments its schema
  requires and the call leaves out fail the call without running it.
  """
  def call(%__MODULE__{function: function} = tool, %Scope{} = scope, arguments) do
    result =
      case missing(tool, arguments) do
        [] -> function.(scope, arguments)
        names -> {:error, "Missing arguments: " <> Enum.join(names, ", ")}
      end

    case result do
      {:ok, data} when is_map(data) ->
        %{content: [text(Jason.encode!(data))], structuredContent: data}

      {:error, reason} ->
        %{content: [text(explain(reason))], isError: true}
    end
  end

  defp missing(%__MODULE__{input_schema: schema}, arguments) do
    schema
    |> Map.get(:required, [])
    |> Enum.reject(&Map.has_key?(arguments, &1))
  end

  defp text(text), do: %{type: "text", text: text}

  defp explain(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> flatten([])
    |> Enum.join("; ")
    |> then(&("Invalid arguments: " <> &1))
  end

  defp explain(:not_found), do: "Not found"
  defp explain(message) when is_binary(message), do: message

  defp flatten(errors, path) when is_map(errors) do
    Enum.flat_map(errors, fn {field, nested} -> flatten(nested, [field | path]) end)
  end

  defp flatten(messages, path) when is_list(messages) do
    name = path |> Enum.reverse() |> Enum.join(".")

    Enum.flat_map(messages, fn
      message when is_binary(message) -> ["#{name} #{message}"]
      nested -> flatten(nested, path)
    end)
  end
end
