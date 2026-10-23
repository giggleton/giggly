defmodule Giggly.Datasets do
  @moduledoc """
  Datasets to plot, for the examples in Giggly's notebooks and for your own: copies of tables R
  and ggplot2 ship.

  Each dataset is a keyword list of columns, in the dataset's own order, which `Giggly.Plot.new/2`
  reads as a table, as do Explorer's `DataFrame.new/1` and Kino's data table. A column of numbers
  holds integers or floats, as each dataset's doc shows; a name is a string, a date a `Date`, and
  a value the data lacks `nil`.
  Each is kept in Giggly's `priv/datasets` with a header saying where it came from, and read when
  Giggly compiles, so asking for one reads nothing.
  """

  # A dataset is data: it calls only `Giggly.Factor`, to give a factor R's levels, and nothing in
  # Giggly calls it.
  use Boundary, deps: [Giggly.Factor], exports: []

  alias Giggly.Factor

  @mtcars_path Application.app_dir(:giggly, "priv/datasets/mtcars.csv")
  @external_resource @mtcars_path

  @mpg_path Application.app_dir(:giggly, "priv/datasets/mpg.csv")
  @external_resource @mpg_path

  @diamonds_path Application.app_dir(:giggly, "priv/datasets/diamonds.csv")
  @external_resource @diamonds_path

  @economics_path Application.app_dir(:giggly, "priv/datasets/economics.csv")
  @external_resource @economics_path

  @economics_long_path Application.app_dir(:giggly, "priv/datasets/economics_long.csv")
  @external_resource @economics_long_path

  @txhousing_path Application.app_dir(:giggly, "priv/datasets/txhousing.csv")
  @external_resource @txhousing_path

  # How each of mtcars's columns is read; the file's header gives their order.
  @mtcars_types [
    model: :string,
    mpg: :float,
    cyl: :float,
    disp: :float,
    hp: :float,
    drat: :float,
    wt: :float,
    qsec: :float,
    vs: :float,
    am: :float,
    gear: :float,
    carb: :float
  ]

  # How each of mpg's columns is read; the file's header gives their order.
  @mpg_types [
    manufacturer: :string,
    model: :string,
    displ: :float,
    year: :integer,
    cyl: :integer,
    trans: :string,
    drv: :string,
    cty: :integer,
    hwy: :integer,
    fl: :string,
    class: :string
  ]

  # R's levels of diamonds's three ordered factors, `levels(diamonds$cut)` and the others in R
  # 4.6.1 with ggplot2 4.0.3, which `diamonds/0` gives the columns read as their labels.
  @diamonds_levels [
    cut: ["Fair", "Good", "Very Good", "Premium", "Ideal"],
    color: ["D", "E", "F", "G", "H", "I", "J"],
    clarity: ["I1", "SI2", "SI1", "VS2", "VS1", "VVS2", "VVS1", "IF"]
  ]

  # How each of diamonds's columns is read; the file's header gives their order. R stores `table`
  # as a double, whole as its values are, and its factors are read as their labels.
  @diamonds_types [
    carat: :float,
    cut: :string,
    color: :string,
    clarity: :string,
    depth: :float,
    table: :float,
    price: :integer,
    x: :float,
    y: :float,
    z: :float
  ]

  # How each of economics's columns is read; the file's header gives their order. R stores every
  # number as a double, whole ones included.
  @economics_types [
    date: :date,
    pce: :float,
    pop: :float,
    psavert: :float,
    uempmed: :float,
    unemploy: :float
  ]

  # How each of economics_long's columns is read; the file's header gives their order.
  @economics_long_types [
    date: :date,
    variable: :string,
    value: :float,
    value01: :float
  ]

  # How each of txhousing's columns is read; the file's header gives their order. R stores `year`
  # and `month` as integers and every other number as a double, whole ones included.
  @txhousing_types [
    city: :string,
    year: :integer,
    month: :integer,
    sales: :float,
    volume: :float,
    median: :float,
    listings: :float,
    inventory: :float,
    date: :float
  ]

  # why: the dataset is read once, at compile time; no IO happens when a dataset is asked for
  # instead of: the values as literals in this module — rejected because it is R's data, kept as
  #   the file R writes so it can be regenerated and diffed against its source apart from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @mtcars_text File.read!(@mtcars_path)

  # why: the dataset is read once, at compile time; no IO happens when a dataset is asked for
  # instead of: the values as literals in this module — rejected because it is ggplot2's data, kept
  #   as the file R writes so it can be regenerated and diffed against its source apart from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @mpg_text File.read!(@mpg_path)

  # why: the dataset is read once, at compile time; no IO happens when a dataset is asked for
  # instead of: the values as literals in this module — rejected because it is ggplot2's data, kept
  #   as the file R writes so it can be regenerated and diffed against its source apart from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @diamonds_text File.read!(@diamonds_path)

  # why: the dataset is read once, at compile time; no IO happens when a dataset is asked for
  # instead of: the values as literals in this module — rejected because it is ggplot2's data, kept
  #   as the file R writes so it can be regenerated and diffed against its source apart from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @economics_text File.read!(@economics_path)

  # why: the dataset is read once, at compile time; no IO happens when a dataset is asked for
  # instead of: the values as literals in this module — rejected because it is ggplot2's data, kept
  #   as the file R writes so it can be regenerated and diffed against its source apart from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @economics_long_text File.read!(@economics_long_path)

  # why: the dataset is read once, at compile time; no IO happens when a dataset is asked for
  # instead of: the values as literals in this module — rejected because it is ggplot2's data, kept
  #   as the file R writes so it can be regenerated and diffed against its source apart from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @txhousing_text File.read!(@txhousing_path)

  # Each dataset's columns, its file's comment lines skipped: each named by its header, an atom
  # its table of types already holds, and read by its type, a float's R writes as NA missing.
  @parsed Map.new(
            [
              mtcars: {@mtcars_text, @mtcars_types},
              mpg: {@mpg_text, @mpg_types},
              diamonds: {@diamonds_text, @diamonds_types},
              economics: {@economics_text, @economics_types},
              economics_long: {@economics_long_text, @economics_long_types},
              txhousing: {@txhousing_text, @txhousing_types}
            ],
            fn {dataset, {text, types}} ->
              columns =
                text
                |> String.split("\n", trim: true)
                |> Enum.reject(fn line -> String.starts_with?(line, "#") end)
                |> Enum.map(fn line -> String.split(line, ",") end)
                |> Enum.zip_with(fn [header | values] ->
                  name = String.to_existing_atom(header)

                  read =
                    case Keyword.fetch!(types, name) do
                      :string ->
                        fn value -> value end

                      :integer ->
                        &String.to_integer/1

                      :float ->
                        fn
                          "NA" ->
                            nil

                          value ->
                            {number, ""} = Float.parse(value)
                            number
                        end

                      :date ->
                        &Date.from_iso8601!/1
                    end

                  {name, Enum.map(values, read)}
                end)

              {dataset, columns}
            end
          )

  # The small datasets are kept as their columns. diamonds and txhousing are kept compressed, their
  # columns in Erlang's external term format, and decoded each time they are asked for: as columns
  # they would be some 18 MB and 2 MB held wherever this module is loaded, a release loading every
  # module at boot, where compressed they are half a megabyte and a tenth of one, decoded in a few
  # tens of milliseconds and a few, with no IO either way.
  @datasets Map.take(@parsed, [:mtcars, :mpg, :economics, :economics_long])
  @diamonds @parsed
            |> Map.fetch!(:diamonds)
            |> :erlang.term_to_binary(compressed: 9)
  @txhousing @parsed
             |> Map.fetch!(:txhousing)
             |> :erlang.term_to_binary(compressed: 9)

  @doc """
  R's `mtcars`: fuel consumption and ten aspects of design and performance for 32 cars (1973-74
  models), from the 1974 *Motor Trend* US magazine (Henderson and Velleman, 1981). Every number
  is a float.

  The columns: `model`; `mpg`, miles per US gallon; `cyl`, cylinders; `disp`, displacement in
  cubic inches; `hp`, gross horsepower; `drat`, rear axle ratio; `wt`, weight in thousands of
  pounds; `qsec`, quarter-mile time in seconds; `vs`, the engine, 0 V-shaped and 1 straight; `am`,
  the transmission, 0 automatic and 1 manual; `gear`, forward gears; `carb`, carburettors.

      iex> mtcars = Giggly.Datasets.mtcars()
      iex> Keyword.keys(mtcars)
      [:model, :mpg, :cyl, :disp, :hp, :drat, :wt, :qsec, :vs, :am, :gear, :carb]
      iex> mtcars |> Keyword.fetch!(:model) |> length()
      32
      iex> Enum.map(mtcars, fn {name, values} -> {name, Enum.at(values, 2)} end)
      [
        model: "Datsun 710",
        mpg: 22.8,
        cyl: 4.0,
        disp: 108.0,
        hp: 93.0,
        drat: 3.85,
        wt: 2.32,
        qsec: 18.61,
        vs: 1.0,
        am: 1.0,
        gear: 4.0,
        carb: 1.0
      ]
  """
  @spec mtcars() :: [{atom(), [String.t() | number()]}]
  def mtcars, do: Map.fetch!(@datasets, :mtcars)

  @doc """
  ggplot2's `mpg`: fuel economy from 1999 to 2008 for 38 popular models of car, 234 cars in all, a
  subset of the data the US Environmental Protection Agency publishes at
  [fueleconomy.gov](https://fueleconomy.gov/), keeping only models with a new release every year
  from 1999 to 2008.

  The columns: `manufacturer`; `model`; `displ`, engine displacement in litres; `year`, of
  manufacture; `cyl`, cylinders; `trans`, the transmission; `drv`, the drive, `"f"` front-wheel,
  `"r"` rear-wheel and `"4"` four-wheel; `cty`, city miles per gallon; `hwy`, highway miles per
  gallon; `fl`, the fuel type; `class`, the type of car.

      iex> mpg = Giggly.Datasets.mpg()
      iex> Keyword.keys(mpg)
      [:manufacturer, :model, :displ, :year, :cyl, :trans, :drv, :cty, :hwy, :fl, :class]
      iex> mpg |> Keyword.fetch!(:model) |> length()
      234
      iex> Enum.map(mpg, fn {name, values} -> {name, Enum.at(values, 2)} end)
      [
        manufacturer: "audi",
        model: "a4",
        displ: 2.0,
        year: 2008,
        cyl: 4,
        trans: "manual(m6)",
        drv: "f",
        cty: 20,
        hwy: 31,
        fl: "p",
        class: "compact"
      ]
  """
  @spec mpg() :: [{atom(), [String.t() | number()]}]
  def mpg, do: Map.fetch!(@datasets, :mpg)

  @doc """
  ggplot2's `diamonds`: the prices and other attributes of 53,940 round cut diamonds.

  The columns: `carat`, the weight; `cut`, the quality of the cut, from `"Fair"`, `"Good"`,
  `"Very Good"` and `"Premium"` to `"Ideal"`; `color`, from `"D"`, the best, to `"J"`, the worst;
  `clarity`, how clear, from `"I1"`, the worst, through `"SI2"`, `"SI1"`, `"VS2"`, `"VS1"`,
  `"VVS2"` and `"VVS1"` to `"IF"`, the best; `depth`, the total depth as a percentage of the
  mean width, `2 * z / (x + y)`; `table`, the width of the top relative to the widest point;
  `price`, in US dollars; and `x`, `y` and `z`, the length, width and depth in millimetres.
  `cut`, `color` and `clarity` are `Giggly.Factor`s with those levels, in that order, and
  ordered, as R's are, so a plot orders them as given here, not alphabetically; each enumerates
  as its values. It is kept compressed and decoded each time it is asked for, in a few tens of
  milliseconds, so bind it once.

      iex> diamonds = Giggly.Datasets.diamonds()
      iex> Keyword.keys(diamonds)
      [:carat, :cut, :color, :clarity, :depth, :table, :price, :x, :y, :z]
      iex> diamonds |> Keyword.fetch!(:price) |> length()
      53940
      iex> Enum.map(diamonds, fn {name, values} -> {name, Enum.at(values, 2)} end)
      [
        carat: 0.23,
        cut: "Good",
        color: "E",
        clarity: "VS1",
        depth: 56.9,
        table: 65.0,
        price: 327,
        x: 4.05,
        y: 4.07,
        z: 2.31
      ]
  """
  @spec diamonds() :: [{atom(), [number()] | Factor.t()}]
  def diamonds do
    @diamonds
    |> :erlang.binary_to_term()
    |> Enum.map(fn {name, values} -> diamonds_column(name, values) end)
  end

  # A column of diamonds as R holds it: one of its ordered factors with R's levels, or as read.
  defp diamonds_column(name, values) do
    case Keyword.fetch(@diamonds_levels, name) do
      {:ok, levels} -> {name, Factor.new(values, levels: levels, ordered: true)}
      :error -> {name, values}
    end
  end

  @doc """
  ggplot2's `economics`: US economic time series, one row a month from July 1967 to April 2015,
  574 in all, from the Federal Reserve Bank of St. Louis's
  [FRED](https://fred.stlouisfed.org/) database.

  The columns: `date`, the month, as a `Date` on its first day; `pce`, personal consumption
  expenditures, in billions of dollars; `pop`, the total population, in thousands; `psavert`, the
  personal savings rate; `uempmed`, the median duration of unemployment, in weeks; and `unemploy`,
  the number unemployed, in thousands. Every number is a float.

      iex> economics = Giggly.Datasets.economics()
      iex> Keyword.keys(economics)
      [:date, :pce, :pop, :psavert, :uempmed, :unemploy]
      iex> economics |> Keyword.fetch!(:date) |> length()
      574
      iex> Enum.map(economics, fn {name, values} -> {name, Enum.at(values, 0)} end)
      [
        date: ~D[1967-07-01],
        pce: 506.7,
        pop: 198712.0,
        psavert: 12.6,
        uempmed: 4.5,
        unemploy: 2944.0
      ]
  """
  @spec economics() :: [{atom(), [Date.t() | number()]}]
  def economics, do: Map.fetch!(@datasets, :economics)

  @doc """
  ggplot2's `economics_long`: `economics/0` in long form, a row for each month and series, 2,870
  in all, so the five series can be drawn as lines of one plot.

  The columns: `date`, the month, as a `Date` on its first day; `variable`, the series, `"pce"`,
  `"pop"`, `"psavert"`, `"uempmed"` or `"unemploy"`, as `economics/0` names its columns; `value`,
  the series' value that month, in its own units; and `value01`, the value rescaled within its
  series, from 0, its lowest, to 1, its highest, so series of different units share an axis.
  Every number is a float.

      iex> economics_long = Giggly.Datasets.economics_long()
      iex> Keyword.keys(economics_long)
      [:date, :variable, :value, :value01]
      iex> economics_long |> Keyword.fetch!(:date) |> length()
      2870
      iex> Enum.map(economics_long, fn {name, values} -> {name, Enum.at(values, 1)} end)
      [
        date: ~D[1967-08-01],
        variable: "pce",
        value: 509.8,
        value01: 0.0002652497197765077
      ]
  """
  @spec economics_long() :: [{atom(), [Date.t() | String.t() | number()]}]
  def economics_long, do: Map.fetch!(@datasets, :economics_long)

  @doc """
  ggplot2's `txhousing`: housing sales in Texas, a row for each month from January 2000 to July
  2015 and each of 46 multiple listing service areas, 8,602 in all, from the TAMU real estate
  center, [trerc.tamu.edu](https://trerc.tamu.edu/).

  The columns: `city`, the area's name; `year` and `month`, of the sales, integers; `sales`, the
  number of sales; `volume`, their total value, in dollars; `median`, the median sale price, in
  dollars; `listings`, the total active listings; `inventory`, the months it would take to sell
  every listing at the current pace of sales; and `date`, the year and month as a decimal, `year +
  (month - 1) / 12`. Every number but the year and month is a float, and a value the data lacks
  is `nil`, as R's is `NA`. It is kept compressed and decoded each time it is asked for, in a few
  milliseconds, so bind it once.

      iex> txhousing = Giggly.Datasets.txhousing()
      iex> Keyword.keys(txhousing)
      [:city, :year, :month, :sales, :volume, :median, :listings, :inventory, :date]
      iex> txhousing |> Keyword.fetch!(:city) |> length()
      8602
      iex> Enum.map(txhousing, fn {name, values} -> {name, Enum.at(values, 2)} end)
      [
        city: "Abilene",
        year: 2000,
        month: 3,
        sales: 130.0,
        volume: 9285000.0,
        median: 58100.0,
        listings: 784.0,
        inventory: 6.8,
        date: 2000.1666666666667
      ]
  """
  @spec txhousing() :: [{atom(), [String.t() | number() | nil]}]
  def txhousing, do: :erlang.binary_to_term(@txhousing)
end
