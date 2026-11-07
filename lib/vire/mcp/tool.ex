defmodule Vire.Mcp.Tool do
  @moduledoc """
  One MCP tool: its name, the description an agent reads, the JSON Schema of
  its arguments, and the function that runs it.

  The function takes the request's scope and the arguments as a map with
  string keys, once they pass the schema. It answers `{:ok, map}`, which
  becomes the result's structured content and a text content holding the same
  JSON, or `{:error, reason}`, which becomes a result with `isError`.

  Arguments the schema refuses, a changeset's errors and `{:invalid, errors}`
  answer `{ok: false, errors: [{path, message}]}` as both the structured
  content and the text. `:not_found` and a message answer a text.
  """

  alias Vire.Accounts.Scope
  alias Vire.Mcp.Schema

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
  refuses fail the call without running it.
  """
  def call(%__MODULE__{function: function} = tool, %Scope{} = scope, arguments) do
    result =
      case Schema.validate(tool.input_schema, arguments) do
        :ok -> function.(scope, arguments)
        {:error, errors} -> {:error, {:invalid, errors}}
      end

    case result do
      {:ok, data} when is_map(data) ->
        %{content: [text(Jason.encode!(data))], structuredContent: data}

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid(changeset_errors(changeset, []))

      {:error, {:invalid, errors}} ->
        invalid(errors)

      {:error, reason} ->
        %{content: [text(explain(reason))], isError: true}
    end
  end

  @doc """
  A changeset's errors as `%{path, message}`, each path the field's under
  `path`, a list of keys and indexes.
  """
  def changeset_errors(%Ecto.Changeset{} = changeset, path) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> flatten(Enum.reverse(path))
  end

  defp invalid(errors) do
    data = %{ok: false, errors: errors}
    %{content: [text(Jason.encode!(data))], structuredContent: data, isError: true}
  end

  defp text(text), do: %{type: "text", text: text}

  defp explain(:not_found), do: "Not found"
  defp explain(message) when is_binary(message), do: message

  defp flatten(errors, path) when is_map(errors) do
    errors
    |> Enum.sort()
    |> Enum.flat_map(fn {field, nested} -> flatten(nested, [field | path]) end)
  end

  defp flatten(messages, path) when is_list(messages) do
    name = path |> Enum.reverse() |> Schema.format_path()

    Enum.flat_map(messages, fn
      message when is_binary(message) -> [%{path: name, message: message}]
      nested -> flatten(nested, path)
    end)
  end
end
