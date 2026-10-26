defmodule Vire.Mcp.SchemaTest do
  use ExUnit.Case, async: true

  alias Vire.Mcp.Schema

  @schema %{
    type: "object",
    properties: %{
      name: %{type: "string", minLength: 1},
      count: %{type: "integer", minimum: 1, maximum: 3},
      on: %{type: "string", format: "date"},
      note: %{type: ["string", "null"]},
      items: %{type: "array", maxItems: 2, items: %{"$ref": "#/$defs/item"}},
      shape: %{
        oneOf: [
          %{
            type: "object",
            properties: %{kind: %{const: "dot"}},
            required: ["kind"],
            additionalProperties: false
          },
          %{
            type: "object",
            properties: %{kind: %{const: "line"}, length: %{type: "number"}},
            required: ["kind", "length"],
            additionalProperties: false
          }
        ]
      },
      either: %{anyOf: [%{type: "string"}, %{type: "object", required: ["first"]}]}
    },
    required: ["name"],
    additionalProperties: false,
    "$defs": %{item: %{type: "object", properties: %{id: %{type: "string", format: "uuid"}}}}
  }

  defp errors(value) do
    case Schema.validate(@schema, value) do
      :ok -> []
      {:error, errors} -> Enum.map(errors, &{&1.path, &1.message})
    end
  end

  test "accepts a value the schema describes" do
    assert errors(%{
             "name" => "x",
             "count" => 2,
             "on" => "2026-11-02",
             "note" => nil,
             "items" => [%{"id" => Ecto.UUID.generate()}],
             "shape" => %{"kind" => "line", "length" => 1.5},
             "either" => %{"first" => 1}
           }) == []
  end

  test "names every error by its path" do
    assert errors(%{
             "name" => " ",
             "count" => 4,
             "on" => "tomorrow",
             "note" => 1,
             "items" => [%{"id" => "x"}, %{}, %{}],
             "extra" => true
           }) == [
             {"extra", "is not a known field"},
             {"count", "must be at most 3"},
             {"items", "must hold at most 2 items"},
             {"items[0].id", "must be a UUID"},
             {"name", "can't be blank"},
             {"note", "must be a string or null"},
             {"on", "must be a date such as 2026-11-02"}
           ]

    assert errors(%{"count" => 1.5}) == [
             {"name", "is required"},
             {"count", "must be a whole number"}
           ]
  end

  test "checks a oneOf against the branch its consts pick" do
    assert errors(%{"name" => "x", "shape" => %{"kind" => "line"}}) ==
             [{"shape.length", "is required"}]

    assert errors(%{"name" => "x", "shape" => %{"kind" => "dot", "length" => 1}}) ==
             [{"shape.length", "is not a known field"}]

    assert errors(%{"name" => "x", "shape" => %{"kind" => "square"}}) ==
             [{"shape", "kind must be one of dot, line"}]
  end

  test "answers the errors of the anyOf branch of the value's type" do
    assert errors(%{"name" => "x", "either" => %{}}) == [{"either.first", "is required"}]
    assert errors(%{"name" => "x", "either" => 1}) == [{"either", "must be a string"}]
  end
end
