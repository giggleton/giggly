defmodule Giggly.Scale.Continuous do
  @moduledoc """
  A continuous scale. `Giggly.Plot.scale_x_continuous/2`, `Giggly.Plot.scale_x_date/2`,
  `Giggly.Plot.scale_x_datetime/2` and `Giggly.Plot.scale_x_time/2` record one with the options
  they are given and no range, and `Giggly.panel_scales/2` returns an axis's trained. Its fields:

    * `range`: the range of the finite numbers it has seen, or `:none` before it has seen any.
    * `transform`: the transformation its values are put through before it sees them, so its
      range is in transformed space: `:identity` for numbers; `:date` for dates, which it sees as
      days since 1970-01-01; `{:datetime, zone, database}` for date-times, which it sees as
      seconds since 1970-01-01 00:00 UTC, a naive one as though its clock were UTC's, `zone`
      being the time zone its breaks are laid and written in, `:default` until its first column
      gives it one, or `:naive` for naive date-times, and `database` the
      `Calendar.TimeZoneDatabase` that reads it; `:time` for times of day, which it sees as
      seconds since midnight; or `:log10`, `:sqrt`, `:reverse` (each value negated) or
      `:reciprocal`, as a plot's scale names one.
    * `palette`: what turns a value's place in its limits into its aesthetic's value: `:identity`
      for a position, left for the coordinate system to place; `{:rescale, {low, high}}` for an
      aesthetic such as alpha or line width, each place, from 0 to 1, rescaled onto `low` to
      `high`; and
      `{:gradient, colors}` for colour and fill, the colour that far along a gradient through
      `colors`, spaced evenly, blended in L*a*b*; and for size, `{:area, {low, high}}`, each
      place's square root rescaled onto `low` to `high`, so a value's area grows with it, or
      `{:abs_area, max}`, the square root of the place's size rescaled onto 0 to `max`.
    * `rescaler`: how a value's place in the limits is found: `:rescale`, its distance from the
      low end over the limits' width; `{:mid, midpoint}`, its distance from the midpoint over twice
      the further end's, so the midpoint is at the middle and the further end at 0 or 1; or `:max`,
      the value over the high end, so 0 is at 0.
    * `na_value`: what a missing value, one not a finite number, or one outside the limits maps
      to: `nil` for a position, alpha, line width and size, grey, `"#7F7F7F"`, for colour and
      fill, or `:none`, no colour.
    * `guide`: the guide that draws it: `:axis` for a position, `:legend` for alpha, line width,
      size and
      `:colorbar` for colour and fill unless a scale function chooses `:legend`, `:none` for
      none, or a legend `Giggly.Plot.guide_legend/1` makes.
    * `name`: its guide's title, `:none` for none, or `:default` for the title its mapping
      gives.
    * `limits`: `{low, high}`, the values it spans whatever the data, in data units, `nil` at an
      end the data decides; once transformed, the two are sorted. A value outside them is
      missing, so its row is not drawn.
    * `breaks` and `minor_breaks`: the values an axis marks, in data units; on a date axis,
      `{:width, [week: 1]}` for a break every step, one of `:day`, `:week`, `:month` and `:year`
      and how many of it, on a date-time axis `:second`, `:minute` and `:hour` too, and on a time
      axis `:second`, `:minute` and `:hour` alone; `:none` for none; or `:default` for those its
      transformation chooses.
    * `labels`: a label for each break; a function handed every break drawn, in data units, a
      time axis's as times of day wrapped past midnight, that returns their labels; on a date,
      date-time or time axis, `{:format, format}`, each break written in `format` by
      `Calendar.strftime/3`, a time's wrapped past midnight; `:none` for none; or `:default` for
      its transformation's.
    * `expand`: how far an axis reaches beyond its limits, `[mult: {low, high}, add: {low, high}]`:
      at each end, that multiple of the limits' width plus that constant.
  """

  # Use it through `Giggly.Scale`; the transformation is resolved by `Scales.Transform`.

  alias Scales.{Bounds, DataRange, Transform}

  # Every field's default is a position scale's before it has seen any data: the identity
  # transformation and palette, places between the limits' ends, an axis, and every option the
  # default, ggplot2's 5% of the limits' width at each end among them.
  defstruct range: :none,
            transform: :identity,
            palette: :identity,
            rescaler: :rescale,
            na_value: nil,
            guide: :axis,
            name: :default,
            limits: {nil, nil},
            breaks: :default,
            minor_breaks: :default,
            labels: :default,
            expand: [mult: {0.05, 0.05}, add: {0, 0}]

  @typedoc """
  A date, date-time or time axis's step between breaks: one unit and how many of it,
  `[week: 1]`, a date-time's or a time's `[hour: 6]`.
  """
  @type date_step :: [
          {:second | :minute | :hour | :day | :week | :month | :year, pos_integer()}
        ]

  @typedoc "A value a date, date-time or time axis places."
  @type time_value :: Date.t() | DateTime.t() | NaiveDateTime.t() | Time.t()

  @type t :: %__MODULE__{
          range: :none | {number(), number()},
          transform:
            :identity
            | :date
            | {:datetime, String.t() | :default | :naive, module()}
            | :time
            | :log10
            | :sqrt
            | :reverse
            | :reciprocal,
          palette:
            :identity
            | {:rescale, {number(), number()}}
            | {:gradient, [String.t()]}
            | {:area, {number(), number()}}
            | {:abs_area, number()},
          rescaler: :rescale | {:mid, number()} | :max,
          na_value: nil | number() | String.t() | :none,
          guide: :axis | :legend | :colorbar | :none | struct(),
          name: :default | :none | String.t(),
          limits: {number() | time_value() | nil, number() | time_value() | nil},
          breaks: :default | :none | [number() | time_value()] | {:width, date_step()},
          minor_breaks: :default | :none | [number() | time_value()] | {:width, date_step()},
          labels:
            :default
            | :none
            | [String.t()]
            | ([number() | time_value()] -> [String.t()])
            | {:format, String.t()},
          expand: [mult: {number(), number()}, add: {number(), number()}]
        }

  # The values put through the scale's transformation, as `Giggly.Scale.transform/2` describes.
  @doc false
  @spec transform(t(), list()) :: list()
  def transform(%__MODULE__{transform: name}, values), do: Transform.transform(name, values)

  # The scale widened to cover the finite numbers in `values`, as `Giggly.Scale.train/3` describes.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%__MODULE__{range: range} = scale, values) do
    %{scale | range: DataRange.train_continuous(range, values)}
  end

  # Each value, `nil` where it is a number outside the limits, as ggplot2's position scales censor
  # (`oob = censor`, `Scales.Bounds.censor/2`).
  @doc false
  @spec censor(t(), list()) :: list()
  def censor(%__MODULE__{} = scale, values), do: Bounds.censor(values, limits(scale))

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
end
