defmodule Scales.Transform.Composition do
  @moduledoc false

  # A composition of transformations, R's `transform_compose()`: `{:compose, [first, ...]}`, each
  # part a transformation's name, a user's own or another composition. Use it through
  # `Scales.Transform`, which checks it here each time it resolves it (`checked!/1`).
  #
  # Values go through each part in turn and come back through each inverse in the other order;
  # `nil` is passed back without a call, as R's inverses keep NA, since an inverse here is handed
  # positions. The derivatives are R's chain rule as R runs it, each part's derivative at the
  # value it is handed times the product so far, from 1, so only where every part has one: one
  # without raises. Breaks and labels are the first part's (design-log §4, the entries beginning
  # "A composition's breaks" and "A composition's labels"): the extent turned back through the
  # later parts into the first's space, squished into its domain and broken there, the breaks
  # transformed on through the later parts, and labels written by the first part from the breaks
  # turned back into its space, `n:` reaching both as it reaches that part. Minor breaks are R's
  # regular ones unreversed, whichever way the composition runs, as R's default.
  #
  # Its domain is R's: the first part's domain transformed, cut to each later part's domain in
  # turn and transformed again, turned back through every inverse into data units, and sorted,
  # each tie kept as R's `max()` and `min()` keep it, but the range's two ends ordered as a pair,
  # where R takes each alone: so the reciprocal then the reversal keeps the whole line where R's
  # two zeros both come out -0 and leave `-Inf, -Inf` (the entry beginning "A composition's
  # domain"); none left raises `ArgumentError`, as R aborts. A date, date-time or time part comes
  # first or raises: its values are not numbers, so its domain is its own, every value, the later
  # parts cutting the line of its positions only to check one is left; it is never squished, and
  # its steps (`Scales.Transform.width/3`) are laid through the first part.

  @behaviour Scales.Transform

  alias Scales.{Double, MinorBreaks, Transform}

  # The module, once the composition is known to hold a date, date-time or time part first or
  # nowhere, and to take some value.
  @doc false
  @spec checked!({:compose, [Transform.name(), ...]}) :: module()
  def checked!({:compose, [_first | rest]} = composition) do
    if Enum.any?(rest, &Transform.temporal?/1) do
      raise ArgumentError,
            "a date, date-time or time transformation comes first in a composition, since " <>
              "its values are not numbers: #{inspect(composition)}"
    end

    domain(composition)
    __MODULE__
  end

  @impl Scales.Transform
  def transform({:compose, parts}, values),
    do: Enum.reduce(parts, values, fn part, current -> Transform.transform(part, current) end)

  @impl Scales.Transform
  def inverse({:compose, parts}, positions), do: back(Enum.reverse(parts), positions)

  @impl Scales.Transform
  def domain({:compose, [first | _rest]} = composition) do
    range = transformed_domain!(composition)

    if Transform.temporal?(first) do
      Transform.domain(first)
    else
      case inverse(composition, range) do
        [low, high] when low in [nil, :nan] or high in [nil, :nan] ->
          raise ArgumentError, "no value passes every part of #{inspect(composition)}"

        [low, high] ->
          ordered(low, high)
      end
    end
  end

  @impl Scales.Transform
  def derivative({:compose, parts}, values) do
    {product, _values} =
      Enum.reduce(parts, {ones(values), values}, fn part, {product, current} ->
        {chained(Transform.derivative(part, current), product),
         Transform.transform(part, current)}
      end)

    product
  end

  @impl Scales.Transform
  def inverse_derivative({:compose, parts}, positions) do
    {product, _positions} =
      parts
      |> Enum.reverse()
      |> Enum.reduce({ones(positions), positions}, fn part, {product, current} ->
        {chained(Transform.inverse_derivative(part, current), product), back([part], current)}
      end)

    product
  end

  @impl Scales.Transform
  def breaks({:compose, [first | rest]}, extent, options) do
    squished = Transform.squish(first, into_first(rest, extent))

    first
    |> Transform.breaks(squished, options)
    |> onward(rest)
  end

  @impl Scales.Transform
  def minor_breaks(_composition, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format({:compose, [first | rest]}, breaks, extent, options) do
    reversed = Enum.reverse(rest)
    first_extent = if extent == :given, do: :given, else: into_first(rest, extent)
    Transform.format(first, back(reversed, breaks), first_extent, options)
  end

  # The breaks a step lays on an axis showing `extent`, laid through a date, date-time or time
  # first part, as `Scales.Transform.width/3` describes.
  @doc false
  @spec width({:compose, [Transform.name(), ...]}, keyword(pos_integer()), {float(), float()}) ::
          [float()]
  def width({:compose, [first | rest]}, step, extent) do
    first
    |> Transform.width(step, into_first(rest, extent))
    |> onward(rest)
  end

  # The domain in transformed space, as R's `transform_compose()` cuts it part by part; a date,
  # date-time or time first part's positions are the whole line.
  defp transformed_domain!({:compose, [first | rest]} = composition) do
    start =
      if Transform.temporal?(first) do
        [:neg_infinity, :infinity]
      else
        {low, high} = Transform.domain(first)
        Transform.transform(first, [low, high])
      end

    case Enum.reduce_while(rest, start, &cut/2) do
      :empty ->
        raise ArgumentError, "no value passes every part of #{inspect(composition)}"

      range ->
        range
    end
  end

  defp cut(_part, [low, high]) when low in [nil, :nan] or high in [nil, :nan], do: {:halt, :empty}

  defp cut(part, [first, second]) do
    {domain_low, domain_high} = Transform.domain(part)
    {range_low, range_high} = ordered(first, second)
    {_smaller_low, lower} = ordered(range_low, domain_low)
    {upper, _larger_high} = ordered(domain_high, range_high)

    if Double.less?(upper, lower),
      do: {:halt, :empty},
      else: {:cont, Transform.transform(part, [lower, upper])}
  end

  # Two values low to high, the first kept where neither is below the other, as R's `max()` and
  # `min()` keep it: so the domain's end on a tie with the range's, and of a pair of zeros taken
  # together, the reciprocal's -0 and +0, the first low and the second high.
  defp ordered(first, second),
    do: if(Double.less?(second, first), do: {second, first}, else: {first, second})

  # Positions turned back through `parts`, in the order given, a `nil` passed on without a call.
  defp back(parts, positions) do
    Enum.reduce(parts, positions, fn part, current ->
      present = Enum.reject(current, &is_nil/1)

      {turned, []} =
        Enum.map_reduce(current, Transform.inverse(part, present), fn
          nil, rest -> {nil, rest}
          _position, [turned | rest] -> {turned, rest}
        end)

      turned
    end)
  end

  # An extent turned back through the later parts into the first's space, low to high.
  defp into_first(rest, {low, high}) do
    [first_end, second_end] = back(Enum.reverse(rest), [low, high])
    ordered(first_end, second_end)
  end

  defp onward(positions, rest),
    do: Enum.reduce(rest, positions, fn part, current -> Transform.transform(part, current) end)

  defp ones(values), do: Enum.map(values, fn _value -> 1.0 end)

  # A part's derivative times the product so far, as R's `*` takes NA and NaN: the first
  # operand's kept.
  defp chained(derivatives, product), do: Enum.zip_with(derivatives, product, &times/2)

  defp times(nil, _product), do: nil
  defp times(:nan, _product), do: :nan
  defp times(_derivative, nil), do: nil
  defp times(derivative, product), do: Double.multiply(derivative, product)
end
