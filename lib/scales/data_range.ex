defmodule Scales.DataRange do
  @moduledoc false

  # The range of the data a scale has seen, as R's scales trains it: a continuous range, the
  # lowest and highest finite number (`train_continuous/2`, R's `train_continuous()`), or a
  # discrete one, the levels seen in order (`train_discrete/3`, R's `train_discrete()`), with the
  # key that orders levels (`level_key/1`) and the key a level is matched by (`key/1`). R calls
  # it a range; Elixir's `Range` has the name.

  # A range, `:none` for none, widened to cover the finite numbers among `values`: R's
  # `scales::train_continuous()`, which a discrete scale's continuous range trains by too.
  @doc false
  @spec train_continuous(:none | {number(), number()}, list()) :: :none | {number(), number()}
  def train_continuous(range, values), do: Enum.reduce(values, range, &widen/2)

  # `nil` and Explorer's non-finite float atoms are not numbers, so only a number widens the range.
  defp widen(value, :none) when is_number(value), do: {value, value}

  defp widen(value, {low, high}) when is_number(value),
    do: {min(low, value), max(high, value)}

  defp widen(_not_a_finite_number, range), do: range

  # A discrete range, its levels and whether they are a factor's (`:none` before any), with
  # `values` merged into its levels, as R's `scales::discrete_range()` merges a range, `levels`
  # the factor's levels they are values of, or `:none`. Values that are none merge nothing, as
  # ggplot2 trains nothing on no rows.
  @doc false
  @spec train_discrete({list(), :none | boolean()}, list(), list() | :none) ::
          {list(), :none | boolean()}
  def train_discrete(range, [], _levels), do: range

  def train_discrete({_held, :none}, values, levels),
    do: {present_levels(values, levels), levels != :none}

  def train_discrete({held, factor}, values, levels) do
    merged =
      merged(ordered_old(held, factor), factor, present_levels(values, levels), levels != :none)

    {merged, factor}
  end

  # The levels `values` bring, as R's `clevels()` with `drop = TRUE` gives them: a factor's levels
  # its values hold, in its levels' order, then the missing value if one is among them; or the
  # distinct values sorted, the missing value last.
  defp present_levels(values, :none) do
    values
    |> Enum.uniq_by(&key/1)
    |> Enum.sort_by(&level_key/1)
  end

  defp present_levels(values, levels) do
    present = MapSet.new(values, &key/1)
    held = Enum.filter(levels, fn level -> MapSet.member?(present, key(level)) end)
    if MapSet.member?(present, nil), do: Enum.concat(held, [nil]), else: held
  end

  # The levels already held as `discrete_range()` reads them before merging: kept in order, the
  # missing value moved last, where the first values were a factor's; else sorted.
  defp ordered_old(old, true), do: Enum.reject(old, &is_nil/1) ++ Enum.filter(old, &is_nil/1)
  defp ordered_old(old, false), do: Enum.sort_by(old, &level_key/1)

  # A factor's levels lead where the held levels' order is not a factor's, so the two swap.
  defp merged(old, false, new, true), do: appended(new, true, old)
  defp merged(old, old_factor, new, _new_factor), do: appended(old, old_factor, new)

  # The levels not yet held follow those held, and the whole is sorted unless the leading levels
  # are a factor's.
  defp appended(old, old_factor, new) do
    held = MapSet.new(old, &key/1)

    case Enum.reject(new, fn level -> MapSet.member?(held, key(level)) end) do
      [] -> old
      added when old_factor -> old ++ added
      added -> Enum.sort_by(old ++ added, &level_key/1)
    end
  end

  # The key that orders discrete values with no levels of their own: `nil` after every present
  # value, which compare in Erlang term order, so strings sort by their bytes and `false` before
  # `true`; a factor's values, dates among them, are ordered by its levels instead. Grouping orders
  # its combinations by the same key, so group ids and axis positions agree.
  @doc false
  @spec level_key(term()) :: {0, term()} | {1, nil}
  def level_key(nil), do: {1, nil}
  def level_key(value), do: {0, value}

  # The key a value is looked up by: a number as a float, so an integer and the float equal to it
  # share one, and adding a zero turns a negative zero into the zero it equals; any other value as
  # it is.
  @doc false
  @spec key(term()) :: term()
  def key(value) when is_number(value), do: value + 0.0
  def key(value), do: value
end
