defmodule Giggly.Guide.Plotmath do
  @moduledoc false

  # A guide's labels laid out as R's plotmath lays out an expression vector's, as ggplot2 draws a
  # scale's labels when they are expressions, as `Scales.Labels.log/2`'s powers are in R. A guide
  # drawing its labels together, as one grob, an axis's or a bar's, holds expressions only where it
  # holds any power (`expressions/1`): each string beside the powers is an expression too,
  # `{:string, text}`, as every element of R's expression vector is, so it is boxed and placed as
  # plotmath boxes and places one, not as text. A legend draws each key's label alone, as ggplot2
  # draws an expression vector's elements one at a time (`alone/1`): a power is an expression and
  # a string text.
  #
  # An expression is laid out in plotmath's display style, at its look's size and family, and in
  # the plain face whatever the look's, as `GEMathText()` sets the plain font before it draws
  # (`layout/3`). It is a box, its width and how far it reaches above its baseline and below, and
  # the pieces of text it is drawn as, each at its own size and face, its start on its baseline
  # placed from the expression's start, as plotmath draws each piece by itself:
  #
  #   * a string is as wide as its widest line, and reaches as high and as deep as its highest and
  #     deepest characters, each measured on its own (`Giggly.Font.box/5`), a line break among
  #     them, as R measures every character of a string it boxes; it is drawn as the graphics
  #     engine draws text, a line at a time, each starting at its start, its last line on the
  #     baseline and each before it a line spacing above, though its box is the one line's;
  #   * a power, `{:power, base, exponent}`, is its base, a string, then its exponent at 0.7 of the
  #     size, script style, starting where the base ends and raised by the larger of 0.95 of the
  #     height of "x" and the exponent's depth and a quarter of that height, as plotmath's
  #     `RenderSup()` raises a superscript after a number (TeX's rule 18, `sigma13`); an exponent
  #     starting with a minus is R's unary minus round the rest, the sign then the rest, with no
  #     space between in script style;
  #   * a signed power, `{:signed, sign, power}`, is the sign, then a sixth of the width of "M",
  #     plotmath's thin space after a unary operator in display style, then the power.
  #
  # A sign is drawn in the symbol face (`Giggly.Font`), `−` (U+2212, R's symbol-font minus) or
  # `+`. Boxes side by side are as wide as both and as high and as deep as the higher and the
  # deeper, plotmath's `CombineBBoxes()`; a box raised reaches higher by as much and less deep.

  alias Giggly.{Font, Theme}

  @typedoc "A power, its base and its exponent each written as text."
  @type power :: {:power, String.t(), String.t()}

  @typedoc "An expression: a power, a power with a sign before it, or a string among them."
  @type t :: power() | {:signed, String.t(), power()} | {:string, String.t()}

  @typedoc """
  An expression's box, in points: its width, and how far it reaches above its baseline and below.
  """
  @type box :: {float(), float(), float()}

  @typedoc """
  A piece of text an expression is drawn as: its text, size and face, and its start on its
  baseline, `{along, up}` in points from the expression's start on its baseline.
  """
  @type piece :: {String.t(), float(), Font.face(), {float(), float()}}

  # The share of its size an exponent is drawn at, plotmath's script style.
  @script_size 0.7

  # The symbol-font text a sign is drawn as: R's unary minus and plus.
  @signs %{"-" => "−", "+" => "+"}

  # A guide's `labels` as R draws them together, as one grob, an axis's or a bar's: each string an
  # expression where any label is one, as an expression vector's every element is, and a missing
  # one (`nil`, which a scale leaves only among powers) an empty string, which plotmath draws as
  # nothing; as they are otherwise.
  @doc false
  @spec expressions([String.t() | t() | nil | :none]) :: [String.t() | t() | :none]
  def expressions(labels) do
    if Enum.any?(labels, &expression?/1),
      do: Enum.map(labels, &as_expression/1),
      else: labels
  end

  # A label as R draws it alone, as a legend draws each key's from an expression vector's
  # element: a power an expression, a string text, and a missing one (`nil`) `NA`, as text.
  @doc false
  @spec alone(String.t() | t() | nil | :none) :: String.t() | t() | :none
  def alone(nil), do: "NA"
  def alone(label), do: label

  # Whether `label` is an expression, laid out by `layout/3`, rather than text.
  @doc false
  @spec expression?(term()) :: boolean()
  def expression?({:string, text}), do: is_binary(text)
  def expression?({:power, base, exponent}), do: is_binary(base) and is_binary(exponent)

  def expression?({:signed, sign, {:power, _base, _exponent} = power}),
    do: Map.has_key?(@signs, sign) and expression?(power)

  def expression?(_label), do: false

  defp as_expression(text) when is_binary(text), do: {:string, text}
  defp as_expression(nil), do: {:string, ""}
  defp as_expression(label), do: label

  # `expression` laid out in `look`, measured with `installed_fonts`: its box and its pieces, in
  # the order plotmath draws them.
  @doc false
  @spec layout(t(), Theme.text(), boolean()) :: {box(), [piece()]}
  def layout(expression, look, installed_fonts) when is_boolean(installed_fonts),
    do: display(expression, {look, installed_fonts})

  defp display({:string, text}, context), do: string(text, size(context), context)

  defp display({:power, base, exponent}, context) do
    size = size(context)
    {x_height, _depth} = box("x", size, :plain, context)
    {{_width, _height, exponent_depth}, _pieces} = superscript = script(exponent, context)
    raise = max(0.95 * x_height, exponent_depth + 0.25 * x_height)
    beside(string(base, size, context), raised(superscript, raise))
  end

  defp display({:signed, sign, power}, context) do
    size = size(context)
    thin_space = width("M", size, :plain, context) / 6

    sign
    |> symbol(size, context)
    |> beside(space(thin_space))
    |> beside(display(power, context))
  end

  # An exponent, at script size: a leading minus R's unary minus round the rest, with no space
  # after it in script style.
  defp script("-" <> rest, context) do
    size = @script_size * size(context)

    "-"
    |> symbol(size, context)
    |> beside(string(rest, size, context))
  end

  defp script(text, context), do: string(text, @script_size * size(context), context)

  # A string's box and its lines, each starting at the string's start, the last on its baseline
  # and each before it a line spacing above, the spacing taken at `size`; an empty line drawn as
  # nothing.
  defp string(text, size, {look, _installed_fonts} = context) do
    lines = String.split(text, "\n")
    count = length(lines)
    spacing = look.line_spacing * size / look.size
    {height, depth} = box(text, size, :plain, context)

    widest =
      lines
      |> Enum.map(fn line -> width(line, size, :plain, context) end)
      |> Enum.max()

    pieces =
      lines
      |> Enum.with_index(fn line, index ->
        {line, size, :plain, {0.0, (count - 1 - index) * spacing}}
      end)
      |> Enum.reject(fn {line, _size, _face, _start} -> line == "" end)

    {{widest, height, depth}, pieces}
  end

  # A sign, in the symbol face, its box as that face measures it.
  defp symbol(sign, size, context) do
    text = Map.fetch!(@signs, sign)
    {height, depth} = box(text, size, :symbol, context)
    {{width(text, size, :symbol, context), height, depth}, [{text, size, :symbol, {0.0, 0.0}}]}
  end

  defp space(width), do: {{width, 0.0, 0.0}, []}

  # Two laid-out parts side by side, the second starting where the first ends.
  defp beside(
         {{first_width, first_height, first_depth}, first_pieces},
         {second_box, second_pieces}
       ) do
    {second_width, second_height, second_depth} = second_box

    {{first_width + second_width, max(first_height, second_height),
      max(first_depth, second_depth)}, first_pieces ++ moved(second_pieces, first_width, 0.0)}
  end

  # A laid-out part raised `amount` points.
  defp raised({{width, height, depth}, pieces}, amount),
    do: {{width, height + amount, depth - amount}, moved(pieces, 0.0, amount)}

  defp moved(pieces, across, up) do
    Enum.map(pieces, fn {text, size, face, {along, above}} ->
      {text, size, face, {along + across, above + up}}
    end)
  end

  defp size({look, _installed_fonts}), do: look.size

  defp width(text, size, face, {look, installed_fonts}),
    do: Font.width(text, size, look.family, face, installed_fonts)

  defp box(text, size, face, {look, installed_fonts}),
    do: Font.box(text, size, look.family, face, installed_fonts)
end
