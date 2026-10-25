defmodule Vire.Training.Constraints do
  @moduledoc false

  import Ecto.Changeset

  @doc """
  Declares the database's rules for a period on `table`: no overlap with a
  sibling, inside the parent's period, and around every child's.
  """
  def period(changeset, table, opts) do
    changeset
    |> exclusion_constraint(:period,
      name: :"#{table}_period_overlap",
      message: "overlaps another #{Keyword.fetch!(opts, :sibling)}"
    )
    |> within_parent(table, opts[:parent])
    |> check_constraint(:period,
      name: :"#{table}_period_contains_children",
      message: "no longer contains all of its #{Keyword.fetch!(opts, :children)}"
    )
  end

  @doc "Adds an error on `rationale` unless the write's rationale has text."
  def require_rationale(changeset, rationale) do
    if is_binary(rationale) and String.trim(rationale) != "" do
      changeset
    else
      add_error(changeset, :rationale, "can't be blank", validation: :required)
    end
  end

  defp within_parent(changeset, _table, nil), do: changeset

  defp within_parent(changeset, table, parent) do
    check_constraint(changeset, :period,
      name: :"#{table}_period_within_parent",
      message: "lies outside its #{parent}"
    )
  end
end
