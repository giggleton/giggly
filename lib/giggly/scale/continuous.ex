defmodule Giggly.Scale.Continuous do
  @moduledoc """
  A continuous scale. `Giggly.Plot.scale_x_continuous/2` and `Giggly.Plot.scale_x_date/2` record
  one with the options they are given and no range, and `Giggly.panel_scales/2` returns an axis's
  trained. Its fields:

    * `range`: the range of the finite numbers it has seen, or `:none` before it has seen any.
    * `transform`: the transformation its values are put through before it sees them, so its
      range is in transformed space: `:identity` for numbers; `:date` for dates, which it sees as
      days since 1970-01-01; or `:log10`, `:sqrt`, `:reverse` (each value negated) or
      `:reciprocal`, as a plot's scale names one.
    * `palette`: what turns a value's place in its limits into its aesthetic's value: `:identity`
      for a position, left for the coordinate system to place; `{:rescale, {low, high}}` for an
      aesthetic such as alpha, each place, from 0 to 1, rescaled onto `low` to `high`; and
      `{:gradient, colors}` for colour and fill, the colour that far along a gradient through
      `colors`, spaced evenly, blended in L*a*b*.
    * `midpoint`: the value a gradient's middle colour stands at, so each value's place is its
      distance from the midpoint, the end further from it at 0 or 1; `:none` for none, each value
      placed between the limits' ends.
    * `na_value`: what a missing value, one not a finite number, or one outside the limits maps
      to: `nil` for a position and alpha, grey, `"#7F7F7F"`, for colour and fill, or `:none`, no
      colour.
    * `guide`: the guide that draws it: `:axis` for a position, `:legend` for alpha and
      `:colorbar` for colour and fill unless a scale function chooses `:legend`, `:none` for
      none, or a legend `Giggly.Plot.guide_legend/1` makes.
    * `name`: its guide's title, `:none` for none, or `:default` for the title its mapping
      gives.
    * `limits`: `{low, high}`, the values it spans whatever the data, in data units, `nil` at an
      end the data decides; once transformed, the two are sorted. A value outside them is
      missing, so its row is not drawn.
    * `breaks` and `minor_breaks`: the values an axis marks, in data units; on a date axis,
      `{:width, [week: 1]}` for a break every step, one of `:day`, `:week`, `:month` and `:year`
      and how many of it; `:none` for none; or `:default` for those its transformation chooses.
    * `labels`: a label for each break; a function handed every break drawn, in data units, that
      returns their labels; on a date axis, `{:format, format}`, each date written in `format` by
      `Calendar.strftime/3`; `:none` for none; or `:default` for its transformation's.
    * `expand`: how far an axis reaches beyond its limits, `[mult: {low, high}, add: {low, high}]`:
      at each end, that multiple of the limits' width plus that constant.
  """

  # Use it through `Giggly.Scale`; the transformation is resolved by `Giggly.Scale.Transform`.

  alias Giggly.Scale.Transform

  # Every field's default is a position scale's before it has seen any data: the identity
  # transformation and palette, no midpoint, an axis, and every option the default, ggplot2's 5%
  # of the limits' width at each end among them.
  defstruct range: :none,
            transform: :identity,
            palette: :identity,
            midpoint: :none,
            na_value: nil,
            guide: :axis,
            name: :default,
            limits: {nil, nil},
            breaks: :default,
            minor_breaks: :default,
            labels: :default,
            expand: [mult: {0.05, 0.05}, add: {0, 0}]

  @typedoc "A date axis's step between breaks: one unit and how many of it, `[week: 1]`."
  @type date_step :: [{:day | :week | :month | :year, pos_integer()}]

  @type t :: %__MODULE__{
          range: :none | {number(), number()},
          transform: :identity | :date | :log10 | :sqrt | :reverse | :reciprocal,
          palette: :identity | {:rescale, {number(), number()}} | {:gradient, [String.t()]},
          midpoint: :none | number(),
          na_value: nil | number() | String.t() | :none,
          guide: :axis | :legend | :colorbar | :none | struct(),
          name: :default | :none | String.t(),
          limits: {number() | Date.t() | nil, number() | Date.t() | nil},
          breaks: :default | :none | [number() | Date.t()] | {:width, date_step()},
          minor_breaks: :default | :none | [number() | Date.t()] | {:width, date_step()},
          labels:
            :default
            | :none
            | [String.t()]
            | ([number() | Date.t()] -> [String.t()])
            | {:format, String.t()},
          expand: [mult: {number(), number()}, add: {number(), number()}]
        }

  # The values put through the scale's transformation, as `Giggly.Scale.transform/2` describes.
  @doc false
  @spec transform(t(), list()) :: list()
  def transform(%__MODULE__{transform: name}, values), do: Transform.transform(name, values)

  # The scale widened to cover the finite numbers in `values`, as `Giggly.Scale.train/2` describes.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%__MODULE__{range: range} = scale, values) do
    %{scale | range: train_range(range, values)}
  end

  # A range, `:none` for none, widened to cover the finite numbers among `values`: R's
  # `scales::train_continuous()`, which a discrete scale's continuous range trains by too.
  @doc false
  @spec train_range(:none | {number(), number()}, list()) :: :none | {number(), number()}
  def train_range(range, values), do: Enum.reduce(values, range, &widen/2)

  # Each value, `nil` where it is a number outside the limits, as ggplot2's position scales censor
  # (`oob = censor`, finite values only): an infinite end, `:infinity` or `:neg_infinity`, is kept,
  # so a rectangle reaching the panel's edge still does.
  @doc false
  @spec censor(t(), list()) :: list()
  def censor(%__MODULE__{} = scale, values) do
    {low, high} = limits(scale)
    Enum.map(values, fn value -> censored(value, low, high) end)
  end

  # The scale's limits in transformed space, as ggplot2 transforms a scale's limits when it makes
  # the scale: each end given put through the transformation, `nil` where the data decides, and
  # the two sorted when both are given, so either order names the same axis. A given end outside
  # the transformation's domain cannot be placed, and raises, where ggplot2 fails.
  @doc false
  @spec limits(t()) :: {number() | nil, number() | nil}
  def limits(%__MODULE__{limits: {low, high} = given, transform: name}) do
    [low_position, high_position] = Transform.transform(name, [low, high])

    unless placed?(low, low_position) and placed?(high, high_position) do
      raise ArgumentError,
            "a scale's limits #{inspect(given)} fall outside its #{name} transformation's domain"
    end

    sorted(low_position, high_position)
  end

  defp placed?(nil, nil), do: true
  defp placed?(_given, position), do: is_number(position)

  defp sorted(low, high) when is_number(low) and is_number(high) and low > high, do: {high, low}
  defp sorted(low, high), do: {low, high}

  defp censored(value, low, _high) when is_number(value) and is_number(low) and value < low,
    do: nil

  defp censored(value, _low, high) when is_number(value) and is_number(high) and value > high,
    do: nil

  defp censored(value, _low, _high), do: value

  # `nil` and Explorer's non-finite float atoms are not numbers, so only a number widens the range.
  defp widen(value, :none) when is_number(value), do: {value, value}

  defp widen(value, {low, high}) when is_number(value),
    do: {min(low, value), max(high, value)}

  defp widen(_not_a_finite_number, range), do: range
end
