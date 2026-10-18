defmodule Giggly.AsCharacter do
  @moduledoc false

  # A value written as text as R's `as.character()` writes it, which ggplot2 does wherever it
  # writes a value it was given rather than a break it computed: a text's label, and a discrete
  # scale's level, since `factor()` labels each level by `as.character()` of its value.
  #
  # Text is written as it is, a whole number with no decimal point, a float in up to 15
  # significant digits, the zeros after its last significant one dropped, in plain or scientific
  # notation whichever is shorter, a tie going to plain (`21`, `2.62`, `0.333333333333333`,
  # `1e+05`, `123456`), the non-finite floats as `Inf`, `-Inf` and `NaN`, `TRUE` and `FALSE`, any
  # other atom by its name, and a date as `2020-01-02`. A missing value has no text here: each
  # caller says what it does with one, as text leaves the row out and a scale labels it `NA`.
  #
  # Its own boundary, depending on nothing, as `Giggly.Resolution` is R's `resolution()`: the text
  # geom and the scales both list it, so the rule has one home though neither lists the other.
  use Boundary, deps: [], exports: []

  # The text `value` is written as.
  @doc false
  @spec text(term()) :: String.t()
  def text(value) when is_binary(value), do: value
  def text(value) when is_integer(value), do: Integer.to_string(value)
  def text(true), do: "TRUE"
  def text(false), do: "FALSE"
  def text(:infinity), do: "Inf"
  def text(:neg_infinity), do: "-Inf"
  def text(:nan), do: "NaN"
  def text(value) when is_float(value), do: float_text(value)
  def text(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  def text(%Date{} = value), do: Date.to_string(value)

  # A float as R writes one: rounded to 15 significant digits, the zeros after its last
  # significant one dropped, then in plain notation, or in scientific when that is shorter.
  defp float_text(value) when value == 0, do: "0"

  defp float_text(value) do
    [mantissa, exponent] =
      value
      |> abs()
      |> :erlang.float_to_binary(scientific: 14)
      |> String.split("e")

    digits =
      mantissa
      |> String.replace(".", "")
      |> String.trim_trailing("0")

    exponent = String.to_integer(exponent)
    plain = plain_notation(digits, exponent)
    scientific = scientific_notation(digits, exponent)
    sign = if value < 0, do: "-", else: ""

    if String.length(plain) <= String.length(scientific),
      do: sign <> plain,
      else: sign <> scientific
  end

  defp plain_notation(digits, exponent) when exponent < 0,
    do: "0." <> String.duplicate("0", -exponent - 1) <> digits

  defp plain_notation(digits, exponent) do
    whole = String.pad_trailing(digits, exponent + 1, "0")
    {integer_part, fraction} = String.split_at(whole, exponent + 1)
    if fraction == "", do: integer_part, else: integer_part <> "." <> fraction
  end

  defp scientific_notation(digits, exponent) do
    {first, rest} = String.split_at(digits, 1)
    mantissa = if rest == "", do: first, else: first <> "." <> rest
    sign = if exponent < 0, do: "-", else: "+"

    exponent_digits =
      exponent
      |> abs()
      |> Integer.to_string()
      |> String.pad_leading(2, "0")

    mantissa <> "e" <> sign <> exponent_digits
  end
end
