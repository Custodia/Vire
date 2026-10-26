defmodule Vire.Training.Structure do
  @moduledoc """
  The shape of a session's `structure`. Its `steps` is a list of steps, each
  with a `kind` (warmup, work, recovery, cooldown or rest), `seconds`, and
  optionally a `zone` from 1 to 5, a `target` and a `note`. A step may instead
  be a repeat: a `repeat` count with its own `steps`. Keys besides `steps` are
  the caller's own and are not checked.
  """

  @kinds ~w(warmup work recovery cooldown rest)

  @doc "The step kinds a structure accepts."
  def kinds, do: @kinds

  @doc "Checks `structure`'s steps, answering `:ok` or `{:error, message}`."
  def validate(%{} = structure) do
    case fetch(structure, "steps") do
      :error -> :ok
      {:ok, steps} -> steps(steps, "steps")
    end
  end

  defp steps(steps, path) when is_list(steps) do
    steps
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {step, index}, :ok ->
      case step(step, "#{path}[#{index}]") do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp steps(_steps, path), do: {:error, "#{path} must be a list of steps"}

  defp step(step, path) when is_map(step) do
    case fetch(step, "repeat") do
      {:ok, count} -> repeat(step, count, path)
      :error -> single(step, path)
    end
  end

  defp step(_step, path), do: {:error, "#{path} must be an object"}

  defp repeat(step, count, path) do
    cond do
      not (is_integer(count) and count >= 1) ->
        {:error, "#{path}.repeat must be a whole number of at least 1"}

      not match?({:ok, [_ | _]}, fetch(step, "steps")) ->
        {:error, "#{path}.steps must list the steps to repeat"}

      true ->
        {:ok, inner} = fetch(step, "steps")
        steps(inner, "#{path}.steps")
    end
  end

  defp single(step, path) do
    with :ok <-
           check(step, "kind", path, &(&1 in @kinds), "must be one of #{Enum.join(@kinds, ", ")}"),
         :ok <-
           check(
             step,
             "seconds",
             path,
             &(is_integer(&1) and &1 > 0),
             "must be a whole number of seconds above 0"
           ),
         :ok <- optional(step, "zone", path, &(&1 in 1..5), "must be a whole number from 1 to 5"),
         :ok <- optional(step, "target", path, &is_binary/1, "must be a string") do
      optional(step, "note", path, &is_binary/1, "must be a string")
    end
  end

  defp check(step, key, path, valid?, message) do
    case fetch(step, key) do
      {:ok, value} -> if valid?.(value), do: :ok, else: {:error, "#{path}.#{key} #{message}"}
      :error -> {:error, "#{path}.#{key} is required"}
    end
  end

  defp optional(step, key, path, valid?, message) do
    case fetch(step, key) do
      {:ok, nil} -> :ok
      {:ok, _value} -> check(step, key, path, valid?, message)
      :error -> :ok
    end
  end

  # Structures written from Elixir may carry atom keys until they are stored.
  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, String.to_atom(key))
    end
  end
end
