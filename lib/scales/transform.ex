defmodule Scales.Transform do
  @moduledoc """
  The transformation a continuous scale puts its values through before it trains on them, named
  by a value (`t:name/0`): values into transformed space (`transform/2`) and back
  (`inverse/2`), and an axis's default breaks (`breaks/3`), minor breaks (`minor_breaks/3`) and
  labels (`format/3`) there, as R's transformation objects carry them; for a transformation of
  numbers, also the derivatives both ways (`derivative/2`, `inverse_derivative/2`) and the range
  data takes in transformed space (`trim_to_domain/2`).

  Breaks are found as on an axis showing an extent in transformed space: the extent is squished
  into the transformation's domain (`squish/2`), turned back into data units and broken there,
  and the breaks transformed back, in the order that leaves them, so a reversing transformation's
  descend. Some may fall outside the extent; which to keep is the caller's. Labels are written
  from the breaks turned back, `10^x` under log10; a date's depend on the step chosen for the
  whole axis, so `format/3` is handed the extent too. A date, date-time or time transformation
  also lays breaks a calendar or clock step apart (`width/3`).

  A value the transformation cannot place, below a logarithm's or the square root's domain,
  becomes `:nan`, R's `NaN`; a value placed at an infinity is `:infinity` or `:neg_infinity`, and a
  missing one stays `nil`.

  ## Compositions

  `{:compose, [first, second, ...]}` puts values through each transformation in turn, R's
  `transform_compose()`: `{:compose, [:log10, :reverse]}` is a log axis drawn high to low. Its
  breaks and labels are its first part's, found on the extent turned back into that part's space,
  and `n:` reaches them as it reaches that part; its minor breaks are
  `Scales.MinorBreaks.regular/3`'s, unreversed whichever way it runs, as R's; it has derivatives
  where every part has them, by the chain rule. Its domain is what every part takes: the first
  part's domain transformed, cut to the next part's, transformed again, and so on, turned back
  into data units, so `{:compose, [:sqrt, :log10]}` takes values from 1e-200 up, and a
  composition no value passes raises `ArgumentError`. A date, date-time or time transformation
  may come first, and the composition then takes and gives its values, its breaks, labels and
  steps (`width/3`) its first part's, so `{:compose, [:date, :reverse]}` is a date axis drawn
  late to early; anywhere else it raises `ArgumentError`.

      iex> Scales.Transform.transform({:compose, [:log10, :reverse]}, [1, 10, 100])
      [-0.0, -1.0, -2.0]

      iex> Scales.Transform.format({:compose, [:log10, :reverse]}, [-0.0, -1.0, -2.0], {-2.1, 0.1})
      ["1", "10", "100"]

  ## A transformation of your own

  `new/2` makes one from its functions, R's `new_transform()`, and it is given wherever a name is,
  a composition's parts too. Each function takes one value and returns a number, `:infinity`,
  `:neg_infinity`, `:nan` or `nil`. The transformation is handed every value in its domain, an
  integer as a float, and the domain's own ends among them, since an axis is bounded by them;
  `nil` and `:nan` are never handed over, and a value outside the domain becomes `:nan` without
  it. So a transformation on the whole line, the default domain, handles both infinities, as R's
  functions do through their arithmetic; its inverse is handed the transformation's values at
  the domain's ends, and handles them too.

      iex> cube =
      ...>   Scales.Transform.new("cube",
      ...>     transform: fn
      ...>       :infinity -> :infinity
      ...>       :neg_infinity -> :neg_infinity
      ...>       value -> value * value * value
      ...>     end,
      ...>     inverse: fn
      ...>       :infinity -> :infinity
      ...>       :neg_infinity -> :neg_infinity
      ...>       position when position < 0 -> -:math.pow(-position, 1 / 3)
      ...>       position -> :math.pow(position, 1 / 3)
      ...>     end
      ...>   )
      iex> Scales.Transform.transform(cube, [2, -0.5, nil])
      [8.0, -0.125, nil]
      iex> Scales.Transform.breaks(cube, {-1100.0, 1100.0})
      [-1000.0, -125.0, 0.0, 125.0, 1000.0]
      iex> Scales.Transform.format(cube, [-1000.0, -125.0, 0.0, 125.0, 1000.0], {-1100.0, 1100.0})
      ["-10", "-5", "0", "5", "10"]

  Any distribution's quantile is one, as `:probit` is the normal's: the Cauchy distribution's on
  the probabilities from 0 to 1, its ends the infinities.

      iex> cauchy =
      ...>   Scales.Transform.new("cauchy",
      ...>     transform: fn
      ...>       probability when probability == 0 -> :neg_infinity
      ...>       probability when probability == 1 -> :infinity
      ...>       probability -> :math.tan(:math.pi() * (probability - 0.5))
      ...>     end,
      ...>     inverse: fn
      ...>       :neg_infinity -> 0.0
      ...>       :infinity -> 1.0
      ...>       quantile -> 0.5 + :math.atan(quantile) / :math.pi()
      ...>     end,
      ...>     domain: {0, 1}
      ...>   )
      iex> Scales.Transform.transform(cauchy, [0, 0.5, 1, 1.5])
      [:neg_infinity, 0.0, :infinity, :nan]
  """

  # The transformation a continuous scale puts its values through before it trains on them: R's
  # `scales` transformation objects (`new_transform()`), which ggplot2's continuous scales hold as
  # their `transform`. A scale records its transformation by name, and the name is resolved here.
  #
  # A transformation carries what R's object carries and a scale reads: the transformation and its
  # inverse, its domain, and its axis's default breaks, minor breaks and labels (R's `breaks`,
  # `minor_breaks` and `format`): a log axis wants powers of ten, a date axis calendar dates. One
  # of numbers carries its derivatives too (R's `d_transform` and `d_inverse`), which the date,
  # date-time, time and span of time transformations have none of, as R's have none.
  #
  # Each is a module implementing this behaviour: the identity (`Transform.Identity`), which a
  # continuous scale of numbers records, as ggplot2's continuous scales default to
  # `transform = "identity"`; the date transformation (`Transform.Date`), which a scale of dates
  # records; the date-time transformation (`Transform.Datetime`), which a scale of date-times
  # records with its time zone and the database that reads it, `{:datetime, zone, database}`, as
  # R's `transform_time(tz)` holds its zone; the time-of-day transformation (`Transform.Time`),
  # which a scale of times records, as ggplot2's `scale_x_time()` records `transform_hms()`; and
  # the logarithms in a base above 1 (`Transform.Log`: `:log`, `:log2`, `:log10`, `{:log, base}`),
  # log1p, exponentials (`Transform.Exp`: `:exp`, `{:exp, base}`), the inverse hyperbolic sine,
  # the pseudo-logarithm, square root, reverse and reciprocal (`Transform.Log1p`,
  # `Transform.Asinh`, `Transform.PseudoLog`, `Transform.Sqrt`, `Transform.Reverse`,
  # `Transform.Reciprocal`), the arcsine square root and inverse hyperbolic tangent
  # (`Transform.Asn`, `Transform.Atanh`), a distribution's quantile (`Transform.Probability`:
  # `:logit`, `:probit`, `{:probability, distribution, options}`), the Box-Cox, modulus and
  # Yeo-Johnson transformations (`Transform.BoxCox`, `Transform.Modulus`, `Transform.YeoJohnson`,
  # built on `Transform.Power`), and a span of time in seconds (`Transform.Timespan`), which a
  # plot's scale names. A name holding a base, a sigma, a distribution's parameters, an exponent,
  # an offset or a unit is refused where it is resolved
  # unless each is a number in range, so every callback reads them unchecked. Every callback is
  # handed the transformation as the scale records it, so one that holds more than its name reads
  # it, as R's object's functions close over theirs. Each finds its
  # breaks as ggplot2's `get_breaks()` does, on the extent turned back into data units, and returns
  # them transformed, in the order that leaves them, so a reversing transformation's descend; its
  # labels are written from the breaks turned back. A default break's label may depend on the
  # extent as well as the break, as a date's format does on the step chosen for the whole axis, so
  # `format/2` is handed both, or `:given` for breaks it did not choose, which a date writes in
  # full.

  alias Scales.{Bounds, Breaks, Double, Labels, MinorBreaks, Transform}

  @derive {Inspect, only: [:name, :domain]}
  defstruct [
    :name,
    :transform,
    :inverse,
    :derivative,
    :inverse_derivative,
    :domain,
    :breaks,
    :minor_breaks,
    :labels
  ]

  @typedoc """
  A transformation of your own, made by `new/2`: its name, its functions and its domain.
  """
  @type t :: %__MODULE__{
          name: String.t(),
          transform: (term() -> term()),
          inverse: (term() -> term()),
          derivative: (term() -> term()) | nil,
          inverse_derivative: (term() -> term()) | nil,
          domain: {number() | :neg_infinity, number() | :infinity},
          breaks:
            ({float(), float()} -> [number()]) | ({float(), float()}, keyword() -> [number()]),
          minor_breaks: ([float()], {float(), float()} -> [float()]),
          labels: ([term()] -> [String.t()])
        }

  @new_options NimbleOptions.new!(
                 transform: [
                   type: {:fun, 1},
                   required: true,
                   doc:
                     "The transformation, of one value: a number, an integer as a float, or " <>
                       "an infinity in the domain, to a number, `:infinity`, `:neg_infinity`, " <>
                       "`:nan` or `nil`."
                 ],
                 inverse: [
                   type: {:fun, 1},
                   required: true,
                   doc: "Its inverse, of one position in transformed space, returning as it does."
                 ],
                 derivative: [
                   type: {:fun, 1},
                   doc:
                     "Its derivative, of one value, for `derivative/2`; without one, " <>
                       "`derivative/2` raises."
                 ],
                 inverse_derivative: [
                   type: {:fun, 1},
                   doc:
                     "Its inverse's derivative, of one position, for `inverse_derivative/2`; " <>
                       "without one, `inverse_derivative/2` raises."
                 ],
                 domain: [
                   type: {:custom, __MODULE__, :validate_domain, []},
                   default: {:neg_infinity, :infinity},
                   doc:
                     "The values it takes, `{low, high}` in data units, each a number or an " <>
                       "infinity, `low` below `high`."
                 ],
                 breaks: [
                   type: {:or, [{:fun, 1}, {:fun, 2}]},
                   default: &Breaks.extended/2,
                   doc:
                     "An axis's breaks, from its limits in data units, `{low, high}`, to " <>
                       "breaks in data units; one of two arguments is also handed " <>
                       "`breaks/3`'s options, so `n:` reaches it, and one of one argument " <>
                       "takes none."
                 ],
                 minor_breaks: [
                   type: {:fun, 2},
                   default: &MinorBreaks.regular/2,
                   doc:
                     "An axis's minor breaks, from its breaks and its extent, both in " <>
                       "transformed space, to minor breaks there."
                 ],
                 labels: [
                   type: {:fun, 1},
                   default: &Labels.plain/1,
                   doc: "An axis's labels, from its breaks turned back into data units."
                 ]
               )

  @breaks_options NimbleOptions.new!(
                    n: [
                      type: :non_neg_integer,
                      doc:
                        "The number of breaks wanted, five when not given, for every " <>
                          "transformation but `:time` and a span of time's: from 1 for the " <>
                          "logarithms in a base " <>
                          "(`:log`, `:log2`, `:log10`, `{:log, base}`), from 0 for dates and " <>
                          "date-times, and from 2 for the rest, as R's own breaks take it."
                    ]
                  )

  @typedoc """
  A transformation, by name: `:identity`, R's `transform_identity()`; `:log` (base e), `:log2`,
  `:log10` and `{:log, base}`, R's `transform_log()`, `transform_log2()`, `transform_log10()` and
  `transform_log(base)`; `:log1p`, R's `transform_log1p()`; `:exp` (base e) and `{:exp, base}`,
  R's `transform_exp()`; `:asinh`, R's `transform_asinh()`; `:pseudo_log` and
  `{:pseudo_log, sigma: sigma, base: base}`, either or both, R's
  `transform_pseudo_log(sigma = 1, base = exp(1))`; `:sqrt`, `:reverse` (each value negated) and
  `:reciprocal`, R's `transform_sqrt()` and its kin; `:asn`, the arcsine square root, and
  `:atanh`, R's `transform_asn()` and `transform_atanh()`; `:logit` and `:probit`, R's
  `transform_logit()` and `transform_probit()`; `{:probability, :normal, mean: mean, sd: sd}` and
  `{:probability, :logistic, location: location, scale: scale}`, either or both, R's
  `transform_probability("norm", mean = 0, sd = 1)` and `transform_probability("logis",
  location = 0, scale = 1)`; `{:boxcox, exponent}` and `{:boxcox, exponent, offset: offset}`,
  R's `transform_boxcox(p, offset = 0)`; `{:modulus, exponent}` and `{:modulus, exponent, offset:
  offset}`, R's `transform_modulus(p, offset = 1)`; `{:yj, exponent}`, the Yeo-Johnson
  transformation, R's `transform_yj(p)`; `:timespan` and `{:timespan, unit}`, a number counted in
  `unit`, `:second` to `:week`, as its seconds, R's `transform_timespan(unit = "secs")`; `:date`,
  a `Date` as its days since 1970-01-01, R's `transform_date()`; `{:datetime, zone, database}`, a
  `DateTime` or `NaiveDateTime` as its seconds since 1970-01-01 00:00 UTC, its breaks laid on
  the clock of `zone`, read by the time zone database `database`, R's `transform_time(tz)`, the
  zone `:default` until a column settles it and `:naive` for naive date-times; `:time`, a
  `Time` as its seconds since midnight, R's `transform_hms()`; `{:compose, [first, second,
  ...]}`, each in turn, R's `transform_compose()`; and a transformation of your own, `t:t/0`,
  made by `new/2`.

  A base is a number above 1, a sigma, a standard deviation or a scale a number above 0, a
  mean, a location or an exponent a number, a Box-Cox offset a number from 0 up and a modulus
  offset one from 1 up, and a name holding any other raises `FunctionClauseError` wherever it is
  handed, where R also takes a base below 1, falling, and gives no axis at 1 or a scale of 0, and a
  modulus offset below 1, which no longer rises. A falling axis is the transformation in a base
  above 1 reversed.
  """
  @type name ::
          :identity
          | :date
          | {:datetime, String.t() | :default | :naive, module()}
          | :time
          | :log
          | :log2
          | :log10
          | {:log, number()}
          | :log1p
          | :exp
          | {:exp, number()}
          | :asinh
          | :pseudo_log
          | {:pseudo_log, [sigma: number(), base: number()]}
          | :sqrt
          | :reverse
          | :reciprocal
          | :asn
          | :atanh
          | :logit
          | :probit
          | {:probability, :normal, [mean: number(), sd: number()]}
          | {:probability, :logistic, [location: number(), scale: number()]}
          | {:boxcox, number()}
          | {:boxcox, number(), [offset: number()]}
          | {:modulus, number()}
          | {:modulus, number(), [offset: number()]}
          | {:yj, number()}
          | :timespan
          | {:timespan, Scales.Breaks.timespan_unit()}
          | {:compose, [name(), ...]}
          | t()

  @typedoc "A break in transformed space: a number, or an infinity or NaN where R's lands one."
  @type break :: float() | :infinity | :neg_infinity | :nan

  # The date, date-time and time transformations, whose data are not numbers.
  defguardp is_temporal(name)
            when name in [:date, :time] or (is_tuple(name) and elem(name, 0) == :datetime)

  # A number or an infinity.
  defguardp is_bound(value) when is_number(value) or value in [:infinity, :neg_infinity]

  # The span of time transformation, of numbers but with no derivatives, as R's has none.
  defguardp is_timespan(name)
            when name == :timespan or (is_tuple(name) and elem(name, 0) == :timespan)

  # A span of time's unit, as `Scales.Breaks.timespan/2` names them.
  defguardp is_unit(unit) when unit in [:second, :minute, :hour, :day, :week]

  # A base a logarithm, an exponential or a pseudo-logarithm takes, and a pseudo-logarithm's sigma
  # or a distribution's spread.
  defguardp is_base(base) when is_number(base) and base > 1
  defguardp is_positive(value) when is_number(value) and value > 0

  # A Box-Cox offset, from 0 up, and a modulus offset, from 1 up, where the modulus rises.
  defguardp is_boxcox_offset(offset) when is_number(offset) and offset >= 0
  defguardp is_modulus_offset(offset) when is_number(offset) and offset >= 1

  # A distribution's parameter by name: a mean or location a number, a standard deviation or a
  # scale a number above 0.
  defguardp is_parameter(distribution, key, value)
            when (distribution == :normal and
                    ((key == :mean and is_number(value)) or (key == :sd and is_positive(value)))) or
                   (distribution == :logistic and
                      ((key == :location and is_number(value)) or
                         (key == :scale and is_positive(value))))

  # The values in transformed space: a number, `nil`, `:infinity`, `:neg_infinity` or `:nan` each,
  # a value outside the domain `:nan`, R's NaN.
  @doc false
  @callback transform(transformation :: name(), values :: list()) :: list()

  # Positions turned back into data units.
  @doc false
  @callback inverse(transformation :: name(), positions :: [number()]) :: list()

  # The domain in data units, R's `domain`: `{:neg_infinity, :infinity}` for one that bounds
  # nothing, every date for the date transformation.
  @doc false
  @callback domain(transformation :: name()) :: Scales.Bounds.range()

  # The breaks of an axis showing `extent`, in transformed space, in the transformation's order;
  # some may fall outside it, a break at an end of a domain the transformation takes to an
  # infinity, logit's 0 and 1, there, as R's. `options` are `breaks/3`'s, validated, and always
  # `[]` for the time and span of time transformations, which count no breaks.
  @doc false
  @callback breaks(transformation :: name(), extent :: {float(), float()}, options :: keyword()) ::
              [break()]

  # The minor breaks between `breaks` on an axis showing `extent`; the breaks themselves may be
  # among them, and some may fall outside the extent.
  @doc false
  @callback minor_breaks(
              transformation :: name(),
              breaks :: [float()],
              extent :: {float(), float()}
            ) :: [float()]

  # The derivative of the transformation at each value, and of its inverse at each position, R's
  # `d_transform` and `d_inverse`, each a double (`t:Scales.double/0`) taken as R's arithmetic
  # takes it. A transformation of numbers alone has them.
  @doc false
  @callback derivative(transformation :: name(), values :: [Scales.double()]) ::
              [Scales.double()]

  @doc false
  @callback inverse_derivative(transformation :: name(), positions :: [Scales.double()]) ::
              [Scales.double()]

  @optional_callbacks derivative: 2, inverse_derivative: 2

  # Each break's label, in the order given: the transformation's own breaks on an axis showing
  # `extent`, found with `options`, `breaks/3`'s, validated, or, for `:given`, breaks a plot gave
  # or a width laid.
  @doc false
  @callback format(
              transformation :: name(),
              breaks :: [float()],
              extent :: {float(), float()} | :given,
              options :: keyword()
            ) :: [String.t()]

  @doc """
  A transformation of your own named `name`, R's `new_transform()`, from its functions, each of
  one value: given wherever a transformation's name is, and as a composition's part. Its domain
  is the whole line unless `domain:` says, its breaks `Scales.Breaks.extended/2`'s on an axis's
  limits in data units, its minor breaks `Scales.MinorBreaks.regular/3`'s and its labels
  `Scales.Labels.plain/1`'s of the breaks turned back, unless `breaks:`, `minor_breaks:` or
  `labels:` say. A missing function, an unknown option, a function of another arity or a domain
  not `{low, high}` raises `NimbleOptions.ValidationError`.

  It is handed every value in its domain, the domain's ends among them, as the module
  documentation describes, and its inverse every position but `nil` and `:nan`: on the whole
  line it handles `:infinity` and `:neg_infinity`.

  ## Options

  #{NimbleOptions.docs(@new_options)}

  ## Examples

      iex> square_root =
      ...>   Scales.Transform.new("square root",
      ...>     transform: &:math.sqrt/1,
      ...>     inverse: fn position -> position * position end,
      ...>     domain: {0, 1.0e300}
      ...>   )
      iex> Scales.Transform.transform(square_root, [4, -1, nil])
      [2.0, :nan, nil]
  """
  @spec new(String.t(), keyword()) :: t()
  def new(name, options) when is_binary(name) do
    validated = NimbleOptions.validate!(options, @new_options)
    struct!(__MODULE__, [name: name] ++ validated)
  end

  # A domain `new/2` takes: two numbers or infinities, the first below the second.
  @doc false
  @spec validate_domain(term()) :: {:ok, {term(), term()}} | {:error, String.t()}
  def validate_domain({low, high} = domain)
      when is_bound(low) and is_bound(high) and low != :infinity and high != :neg_infinity do
    if Double.less?(low, high),
      do: {:ok, domain},
      else: {:error, "expected a domain's low end below its high end, got: #{inspect(domain)}"}
  end

  def validate_domain(domain),
    do:
      {:error, "expected a domain {low, high} of numbers or infinities, got: #{inspect(domain)}"}

  @doc """
  The values put through the transformation `name`.

  ## Examples

      iex> Scales.Transform.transform(:log10, [1, 10, 100, 0, -1, nil])
      [0.0, 1.0, 2.0, :neg_infinity, :nan, nil]

      iex> Scales.Transform.transform(:date, [~D[1970-01-11], nil])
      [10.0, nil]
  """
  @spec transform(name(), list()) :: list()
  def transform(name, values), do: module(name).transform(name, values)

  @doc """
  Positions in transformed space turned back into data units by the transformation `name`.

  ## Examples

      iex> Scales.Transform.inverse(:log10, [0.0, 1.0, 2.0])
      [1.0, 10.0, 100.0]
  """
  @spec inverse(name(), [number()]) :: list()
  def inverse(name, positions), do: module(name).inverse(name, positions)

  # As ggplot2's `get_breaks()` squishes its limits with `oob_squish()` into the domain
  # transformed, its ends sorted: so a transformation of every number whose values are bounded,
  # yj's below 1 for a negative exponent, squishes there too, and a domain transformed to no width,
  # the reciprocal's two zeros, squishes nothing, as R leaves it. No domain transforms to NaN,
  # which R drops. A date's, date-time's or time's domain is every one, so it squishes nothing.
  @doc """
  The extent `{low, high}`, in transformed space, squished into the domain of the transformation
  `name`, transformed: each end outside it moved onto it, as R's `oob_squish()` moves it, so
  log10's breaks are not sought below `-100`, and onto a bound the values of a transformation of
  every number never pass, the Yeo-Johnson transformation's 1 for an exponent of -1. A date's,
  date-time's or time's is never squished.

  ## Examples

      iex> Scales.Transform.squish(:log10, {-200.0, 2.0})
      {-100.0, 2.0}
  """
  @spec squish(name(), {float(), float()}) :: {float(), float()}
  def squish(name, extent) do
    if temporal?(name) do
      extent
    else
      {domain_low, domain_high} = domain(name)
      [first, second] = transform(name, [domain_low, domain_high])
      squished(extent, {Double.minimum(first, second), Double.maximum(first, second)})
    end
  end

  defp squished({low, high} = extent, domain) do
    if Bounds.zero_range?(domain) do
      extent
    else
      [squished_low, squished_high] = Bounds.squish([low, high], domain)
      {squished_low, squished_high}
    end
  end

  @doc """
  The range `values` take in transformed space under the transformation `name`, R's
  `trim_to_domain()`: their range, `nil` and `:nan` left out, squished into the domain and its
  ends transformed, as `{low, high}`; `:none` with no value to range over, where R warns. Only a
  transformation of numbers takes one: a date's, date-time's or time's raises
  `FunctionClauseError`.

  The range is taken before the transformation, so the reciprocal of a range across zero is the
  reciprocals of its ends, and an infinity is kept, not squished, so one outside the domain
  transforms to `:nan`, which makes both ends `:nan`, as R's `range()` makes them.

  ## Examples

      iex> Scales.Transform.trim_to_domain(:log10, [-5, 0, 10, 1000, nil])
      {-100.0, 3.0}

      iex> Scales.Transform.trim_to_domain(:reciprocal, [-5, 0, 10, 1000])
      {-0.2, 0.001}

      iex> Scales.Transform.trim_to_domain(:log10, [:neg_infinity, 5])
      {:nan, :nan}

      iex> Scales.Transform.trim_to_domain(:sqrt, [nil, :nan])
      :none
  """
  @spec trim_to_domain(name(), [Scales.double()]) :: {Scales.double(), Scales.double()} | :none
  def trim_to_domain(name, values) when not is_temporal(name) do
    if temporal?(name) do
      raise ArgumentError,
            "#{inspect(name)} takes dates, date-times or times, not numbers, so it has no " <>
              "range to trim to its domain"
    end

    case Enum.reduce(values, :none, &widened/2) do
      :none -> :none
      {low, high} -> trimmed(name, [low, high])
    end
  end

  # A range widened to cover a value, R's `range(na.rm = TRUE)`: each end kept where the value
  # is not beyond it, so of `-0.0` and `0.0` the first is both ends, as R's.
  defp widened(value, range) when value in [nil, :nan], do: range
  defp widened(value, :none), do: {value, value}

  defp widened(value, {low, high}),
    do: {Double.minimum(low, value), Double.maximum(high, value)}

  defp trimmed(name, ends) do
    [first, last] = transform(name, Bounds.squish(ends, domain(name)))
    {Double.minimum(first, last), Double.maximum(first, last)}
  end

  @doc """
  The derivative of the transformation `name` at each of `values`, R's `d_transform`, each a
  double (`t:Scales.double/0`), its infinities and NaN as R's arithmetic gives them. Only a
  transformation of numbers has one: a date's, date-time's, time's or span of time's raises
  `FunctionClauseError`.

  ## Examples

      iex> Scales.Transform.derivative(:sqrt, [0.25, 0, -1, nil])
      [1.0, :infinity, :nan, nil]

      iex> Scales.Transform.derivative(:identity, [3, nil])
      [1.0, 1.0]
  """
  @spec derivative(name(), [Scales.double()]) :: [Scales.double()]
  def derivative(name, values) when not is_temporal(name) and not is_timespan(name),
    do: module(name).derivative(name, values)

  @doc """
  The derivative of the inverse of the transformation `name` at each of `positions`, in
  transformed space, R's `d_inverse`, as `derivative/2` gives the transformation's.

  ## Examples

      iex> Scales.Transform.inverse_derivative(:sqrt, [0.5, -2, :infinity])
      [1.0, -4.0, :infinity]
  """
  @spec inverse_derivative(name(), [Scales.double()]) :: [Scales.double()]
  def inverse_derivative(name, positions) when not is_temporal(name) and not is_timespan(name),
    do: module(name).inverse_derivative(name, positions)

  @doc """
  The default breaks, in transformed space, of an axis showing `extent` under the transformation
  `name`, in the order the transformation leaves them, some outside the extent, those at an end
  of a domain transformed to an infinity there, as logit's 0 and 1, which no extent reaches:
  extended breaks (`Scales.Breaks`) on the extent in data units, powers of the base and their multiples under a logarithm in a base
  (`Scales.Breaks.log/2`, so powers of e under `:log`), calendar dates under the date
  transformation and clock times under the date-time one, as R's `pretty()` finds them, and
  spans of time under the time and span of time ones, as `Scales.Breaks.timespan/2` finds them.
  Under the Box-Cox, modulus and Yeo-Johnson transformations an end of the extent that turns back
  to an infinity, past a bound their values never reach, is set aside and the breaks found on the
  other end alone, as R's sit there; none where both do.

  `n:` asks for that many: of `Scales.Breaks.log/2` under a logarithm in a base, of R's
  `pretty()` under the date and date-time transformations, and of `Scales.Breaks.extended/2`
  under the rest. The time and span of time transformations count no breaks, as R's take no
  number, and raise `ArgumentError` for it; `Scales.Breaks.timespan/2` takes one.

  ## Options

  #{NimbleOptions.docs(@breaks_options)}

  ## Examples

      iex> Scales.Transform.breaks(:identity, {9.225, 35.075})
      [10.0, 15.0, 20.0, 25.0, 30.0, 35.0]

      iex> Scales.Transform.breaks(:identity, {9.225, 35.075}, n: 10)
      [10.0, 12.5, 15.0, 17.5, 20.0, 22.5, 25.0, 27.5, 30.0, 32.5, 35.0]

      iex> Scales.Transform.breaks(:log10, {0.0, 3.0})
      [0.0, 1.0, 2.0, 3.0]

      iex> Scales.Transform.breaks(:log10, {0.0, 6.0}, n: 2)
      [0.0, 4.0]
  """
  @spec breaks(name(), {float(), float()}, keyword()) :: [break()]
  def breaks(name, extent, options \\ []) do
    validated = counted!(name, options)
    module(name).breaks(name, extent, validated)
  end

  # The options validated, but for the time and span of time transformations, which count no
  # breaks, as R's `transform_hms()` and `transform_timespan()` take no number.
  defp counted!(name, options) do
    case NimbleOptions.validate!(options, @breaks_options) do
      [] ->
        []

      validated when name == :time or is_timespan(name) ->
        raise ArgumentError,
              "the #{inspect(name)} transformation counts no breaks, so it takes no " <>
                "#{inspect(Keyword.keys(validated))}; Scales.Breaks.timespan/2 takes a number " <>
                "of breaks between seconds"

      validated ->
        validated
    end
  end

  @doc """
  The default minor breaks between `breaks` on an axis showing `extent` under the transformation
  `name`, in transformed space: `Scales.MinorBreaks.regular/3`'s, reversed for `:reverse`.

  ## Examples

      iex> Scales.Transform.minor_breaks(:identity, [10.0, 20.0, 30.0], {5.0, 35.0})
      [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0]
  """
  @spec minor_breaks(name(), [float()], {float(), float()}) :: [float()]
  def minor_breaks(name, breaks, extent), do: module(name).minor_breaks(name, breaks, extent)

  @doc """
  The default labels of `breaks`, in transformed space, under the transformation `name`: its own
  breaks on an axis showing `extent`, found with `options`, `breaks/3`'s, or, for `:given`, breaks
  it did not choose, the extent squished into the domain as for `breaks/3`. A number's are
  `Scales.Labels.plain/1`'s, written from the breaks turned back, but the Box-Cox, modulus and
  Yeo-Johnson transformations write each of their own from the value in data units it was found
  from, since the round trip can keep as few as three of its digits, and a span of time's are
  `Scales.Labels.timespan/2`'s; a date's in the format of the step its breaks were chosen at, so a date's or date-time's
  breaks found with `n:` are labelled when given the same `n:`, and a given date written in full.

  ## Options

  `breaks/3`'s.

  ## Examples

      iex> Scales.Transform.format(:log10, [0.0, 1.0, 2.0], {0.0, 2.0})
      ["1", "10", "100"]

      iex> extent = {19723.0, 19726.0}
      iex> Scales.Transform.format(:date, Scales.Transform.breaks(:date, extent), extent)
      ["Dec 31", "Jan 01", "Jan 02", "Jan 03", "Jan 04", "Jan 05"]

      iex> Scales.Transform.format(:date, [19723.0], :given)
      ["2024-01-01"]

      iex> extent = {18262.0, 18993.0}
      iex> breaks = Scales.Transform.breaks(:date, extent, n: 20)
      iex> :date |> Scales.Transform.format(breaks, extent, n: 20) |> Enum.take(3)
      ["Jan 2020", "Feb 2020", "Mar 2020"]
  """
  @spec format(name(), [float()], {float(), float()} | :given, keyword()) :: [String.t()]
  def format(name, breaks, extent, options \\ []) do
    validated = counted!(name, options)
    module(name).format(name, breaks, squished_extent(name, extent), validated)
  end

  # The extent as `breaks/3` is handed it, squished into the domain, so a transformation can find
  # its own breaks again.
  defp squished_extent(_name, :given), do: :given
  defp squished_extent(name, extent), do: squish(name, extent)

  @doc """
  The breaks a step lays, written as `Date.shift/2` takes one (`[week: 2]`), on an axis showing
  `extent` under the date, date-time or time transformation `name`, in transformed space, some
  outside it, as R's `breaks_width()` lays them: from the extent's start rounded down to the
  step's unit (a week to its Monday), every step. Only those three transformations have steps.

  ## Examples

      iex> Scales.Transform.width(:date, [week: 2], {19723.0, 19750.0})
      [19723.0, 19737.0, 19751.0]
  """
  @spec width(
          :date | {:datetime, term(), module()} | :time | {:compose, [name(), ...]},
          keyword(pos_integer()),
          {float(), float()}
        ) :: [float()]
  def width(:date = name, step, extent), do: Transform.Date.width(name, step, extent)

  def width({:datetime, _zone, _database} = name, step, extent),
    do: Transform.Datetime.width(name, step, extent)

  def width(:time = name, step, extent), do: Transform.Time.width(name, step, extent)

  def width({:compose, [_first | _rest]} = name, step, extent),
    do: Transform.Composition.width(name, step, extent)

  # The domain of the transformation `name` in data units, R's `domain`.
  @doc false
  @spec domain(name()) :: Bounds.range()
  def domain(name), do: module(name).domain(name)

  # Whether the transformation `name` takes dates, date-times or times: one of theirs, or a
  # composition whose first part is.
  @doc false
  @spec temporal?(name()) :: boolean()
  def temporal?({:compose, [first | _rest]}), do: temporal?(first)
  def temporal?(name) when is_temporal(name), do: true
  def temporal?(_name), do: false

  defp module(:identity), do: Transform.Identity
  defp module(:date), do: Transform.Date
  defp module({:datetime, _zone, _database}), do: Transform.Datetime
  defp module(:time), do: Transform.Time
  defp module(name) when name in [:log, :log2, :log10], do: Transform.Log
  defp module({:log, base}) when is_base(base), do: Transform.Log
  defp module(:log1p), do: Transform.Log1p
  defp module(:exp), do: Transform.Exp
  defp module({:exp, base}) when is_base(base), do: Transform.Exp
  defp module(:asinh), do: Transform.Asinh
  defp module(:pseudo_log), do: Transform.PseudoLog
  defp module({:pseudo_log, [sigma: sigma]}) when is_positive(sigma), do: Transform.PseudoLog
  defp module({:pseudo_log, [base: base]}) when is_base(base), do: Transform.PseudoLog

  defp module({:pseudo_log, [sigma: sigma, base: base]})
       when is_positive(sigma) and is_base(base),
       do: Transform.PseudoLog

  defp module({:pseudo_log, [base: base, sigma: sigma]})
       when is_positive(sigma) and is_base(base),
       do: Transform.PseudoLog

  defp module(:sqrt), do: Transform.Sqrt
  defp module(:reverse), do: Transform.Reverse
  defp module(:reciprocal), do: Transform.Reciprocal
  defp module(:asn), do: Transform.Asn
  defp module(:atanh), do: Transform.Atanh
  defp module(name) when name in [:logit, :probit], do: Transform.Probability

  defp module({:probability, distribution, [{key, value}]})
       when is_parameter(distribution, key, value),
       do: Transform.Probability

  defp module({:probability, distribution, [{first, first_value}, {second, second_value}]})
       when first != second and is_parameter(distribution, first, first_value) and
              is_parameter(distribution, second, second_value),
       do: Transform.Probability

  defp module({:boxcox, exponent}) when is_number(exponent), do: Transform.BoxCox

  defp module({:boxcox, exponent, [offset: offset]})
       when is_number(exponent) and is_boxcox_offset(offset),
       do: Transform.BoxCox

  defp module({:modulus, exponent}) when is_number(exponent), do: Transform.Modulus

  defp module({:modulus, exponent, [offset: offset]})
       when is_number(exponent) and is_modulus_offset(offset),
       do: Transform.Modulus

  defp module({:yj, exponent}) when is_number(exponent), do: Transform.YeoJohnson
  defp module(:timespan), do: Transform.Timespan
  defp module({:timespan, unit}) when is_unit(unit), do: Transform.Timespan
  defp module({:compose, [_first | _rest]} = name), do: Transform.Composition.checked!(name)
  defp module(%Transform{}), do: Transform.Custom
end
