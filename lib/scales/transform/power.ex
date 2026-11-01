defmodule Scales.Transform.Power do
  @moduledoc false

  # The power less one over its exponent, `(base^exponent - 1) / exponent`, which the Box-Cox,
  # modulus and Yeo-Johnson transformations (`Transform.BoxCox`, `Transform.Modulus`,
  # `Transform.YeoJohnson`) are built from as scales' documentation writes them, and its inverse
  # and derivatives, and the breaks and labels the three share. Use it through those modules.
  #
  # An exponent within 1e-7 of zero counts as zero, as R's do, so the power is the base's natural
  # logarithm, turned back by its exponential. Each is evaluated as written, in R's IEEE arithmetic
  # (`Scales.Double`), R's `^` among it, so it gives R's doubles but where the platform's power,
  # logarithm or exponential differs from R's in the last bit: R's `^` is x86's long-double
  # `powl`, which parts from Erlang's on a few, and the subtraction loses every digit, in R as
  # here, where the power is close to 1 (design-log §4, the entry beginning "The Box-Cox, modulus
  # and Yeo-Johnson transformations").
  #
  # The three take extended Wilkinson's breaks on the extent turned back into data units, an end
  # that turns back to an infinity set aside, as R's breaks then sit on the other end alone; none
  # where both do. Each label is written from the break in data units it was found from, found
  # again from the extent, since the round trip through the transformation can keep as few as
  # three of a break's digits; a break that is not one of them, given or alone on an axis of no
  # width, is turned back and rounded to 14 significant digits (`Labels.plain_round_tripped/1`).

  alias Scales.{Breaks, Double, Labels}

  @near_zero 1.0e-7
  @e :math.exp(1)

  # Whether an exponent counts as zero.
  @doc false
  @spec near_zero?(number()) :: boolean()
  def near_zero?(exponent), do: abs(exponent) < @near_zero

  # `(base^exponent - 1) / exponent`, or the base's natural logarithm.
  @doc false
  @spec transformed(Scales.Double.operand(), number()) :: Scales.Double.operand()
  def transformed(base, exponent) do
    if near_zero?(exponent) do
      Double.logarithm(base, @e)
    else
      base
      |> Double.power(exponent)
      |> Double.subtract(1.0)
      |> Double.divide(exponent)
    end
  end

  # `(position * exponent + 1)^(1 / exponent)`, the base `transformed/2` turns back to, or the
  # position's exponential.
  @doc false
  @spec inverted(Scales.Double.operand(), number()) :: Scales.Double.operand()
  def inverted(position, exponent) do
    if near_zero?(exponent) do
      Double.exponential(position)
    else
      position
      |> Double.multiply(exponent)
      |> Double.add(1.0)
      |> Double.power(Double.divide(1.0, exponent))
    end
  end

  # The derivative of `transformed/2` in its base: `base^(exponent - 1)`, or `1 / base`.
  @doc false
  @spec derivative(Scales.Double.operand(), number()) :: Scales.Double.operand()
  def derivative(base, exponent) do
    if near_zero?(exponent),
      do: Double.divide(1.0, base),
      else: Double.power(base, exponent - 1.0)
  end

  # The derivative of `inverted/2`: `(position * exponent + 1)^(1 / exponent - 1)`, or the
  # position's exponential.
  @doc false
  @spec inverse_derivative(Scales.Double.operand(), number()) :: Scales.Double.operand()
  def inverse_derivative(position, exponent) do
    if near_zero?(exponent) do
      Double.exponential(position)
    else
      reciprocal_less_one =
        1.0
        |> Double.divide(exponent)
        |> Double.subtract(1.0)

      position
      |> Double.multiply(exponent)
      |> Double.add(1.0)
      |> Double.power(reciprocal_less_one)
    end
  end

  # `derivative/2`'s (`:transform`) or `inverse_derivative/2`'s (`:inverse`) at a missing value:
  # R's `NA^0`, 1, where the power is 0, else missing, as it is for an exponent that counts as
  # zero, whose derivatives are a quotient and an exponential.
  @doc false
  @spec missing_derivative(number(), :transform | :inverse) :: float() | nil
  def missing_derivative(exponent, function) do
    cond do
      near_zero?(exponent) -> nil
      function == :transform and exponent - 1 == 0 -> 1.0
      function == :inverse and 1 / exponent - 1 == 0 -> 1.0
      true -> nil
    end
  end

  # The breaks of an axis showing `extent` in transformed space, through `inverse` and
  # `transform` of one value each.
  @doc false
  @spec breaks(
          {Scales.double(), Scales.double()},
          (term() -> term()),
          (term() -> term()),
          keyword()
        ) ::
          [Scales.double()]
  def breaks(extent, inverse, transform, options) do
    extent
    |> data_breaks(inverse, options)
    |> Enum.map(transform)
  end

  # The labels of `breaks`, each from the break in data units it was found from on `extent`, or,
  # for breaks given or found elsewhere, turned back and rounded.
  @doc false
  @spec format(
          [Scales.double()],
          {Scales.double(), Scales.double()} | :given,
          (term() -> term()),
          (term() -> term()),
          keyword()
        ) :: [String.t()]
  def format(breaks, :given, inverse, _transform, _options), do: round_tripped(breaks, inverse)

  def format(breaks, extent, inverse, transform, options) do
    # Two breaks the transformed space cannot tell apart share a position; the first labels it.
    found =
      extent
      |> data_breaks(inverse, options)
      |> Enum.reduce(%{}, fn break, found -> Map.put_new(found, transform.(break), break) end)

    if Enum.all?(breaks, fn break -> Map.has_key?(found, break) end) do
      breaks
      |> Enum.map(fn break -> Map.fetch!(found, break) end)
      |> Labels.plain()
    else
      round_tripped(breaks, inverse)
    end
  end

  defp round_tripped(breaks, inverse) do
    breaks
    |> Enum.map(inverse)
    |> Labels.plain_round_tripped()
  end

  # Extended breaks on the extent turned back into data units, an end that turns back to
  # anything but a number set aside, so one alone gives R's breaks on it and none gives none.
  defp data_breaks({low, high}, inverse, options) do
    case Enum.filter([inverse.(low), inverse.(high)], &is_number/1) do
      [] ->
        []

      ends ->
        ends
        |> Enum.min_max()
        |> Breaks.extended(options)
    end
  end
end
