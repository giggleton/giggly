defmodule Scales.DataRange do
  @moduledoc """
  The range of the data a scale has seen, trained a batch of values at a time: a continuous range,
  the lowest and highest finite number (`train_continuous/2`), or a discrete one, the levels seen,
  in order (`train_discrete/3`); with the key that orders values that have no levels of their own
  (`level_key/1`) and the key a value is matched by (`key/1`).

  A range is `:none` until it has seen a value: a continuous one is then `{low, high}`, and a
  discrete one `{levels, factor}`, `factor` saying whether its first values were a factor's,
  whose levels keep the order they came in.
  """

  # R's `train_continuous()` and `train_discrete()`, which fill its `ContinuousRange` and
  # `DiscreteRange`; R calls it a range, and Elixir's `Range` has the name.

  @doc """
  The range, `:none` for none, widened to cover the finite numbers among `values`, R's
  `train_continuous()`: `nil`, `:infinity`, `:neg_infinity` and `:nan` widen nothing.

  ## Examples

      iex> Scales.DataRange.train_continuous(:none, [nil, 3, :infinity, -2])
      {-2, 3}

      iex> Scales.DataRange.train_continuous({-2, 3}, [7])
      {-2, 7}
  """
  @spec train_continuous(:none | {number(), number()}, list()) :: :none | {number(), number()}
  def train_continuous(range, values), do: Enum.reduce(values, range, &widen/2)

  # `nil` and Explorer's non-finite float atoms are not numbers, so only a number widens the range.
  defp widen(value, :none) when is_number(value), do: {value, value}

  defp widen(value, {low, high}) when is_number(value),
    do: {min(low, value), max(high, value)}

  defp widen(_not_a_finite_number, range), do: range

  @doc """
  The discrete range `{levels, factor}`, `{[], :none}` before any, with `values` merged into its
  levels, R's `train_discrete()` with `drop = TRUE`; `levels` are the levels of the factor
  `values` are of, or `:none` for values with none of their own.

  A factor's values bring the levels they hold, in the levels' order, the missing value after
  them; other values bring their distinct values sorted by `level_key/1`, `nil` last. Values are
  matched by `key/1`, so `4` and `4.0` are one level. A factor's levels lead the rest; and once a
  range's first values were a factor's, new values follow its levels, where otherwise every merge
  sorts them all again. No values merge nothing.

  ## Examples

      iex> Scales.DataRange.train_discrete({[], :none}, ["y", nil, "x"], :none)
      {["x", "y", nil], false}

      iex> Scales.DataRange.train_discrete({["x", "y", nil], false}, ["z", "x"], :none)
      {["x", "y", "z", nil], false}

      iex> Scales.DataRange.train_discrete({[], :none}, ["b", "a"], ["c", "b", "a"])
      {["b", "a"], true}
  """
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

  # The levels already held as R's `discrete_range()` reads them before merging: kept in order, the
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
    added = Enum.reject(new, fn level -> MapSet.member?(held, key(level)) end)
    if old_factor, do: old ++ added, else: Enum.sort_by(old ++ added, &level_key/1)
  end

  @doc """
  The key that orders values with no levels of their own: `nil` after every value, and the values
  in Erlang's term order, so numbers come first, strings sort by their bytes and `false` comes
  before `true`. A factor's values are ordered by its levels instead.

  ## Examples

      iex> Enum.sort_by([nil, "b", 2, "a", true], &Scales.DataRange.level_key/1)
      [2, true, "a", "b", nil]
  """
  @spec level_key(term()) :: {0, term()} | {1, nil}
  def level_key(nil), do: {1, nil}
  def level_key(value), do: {0, value}

  @doc """
  The key a value is matched by: a number as a float, so an integer and the float equal to it
  share one, and a negative zero is the zero it equals; any other value as it is.

  ## Examples

      iex> Scales.DataRange.key(4) === Scales.DataRange.key(4.0)
      true

      iex> Scales.DataRange.key(-0.0)
      0.0
  """
  @spec key(term()) :: term()
  def key(value) when is_number(value), do: value + 0.0
  def key(value), do: value
end
