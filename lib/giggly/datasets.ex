defmodule Giggly.Datasets do
  @moduledoc """
  Datasets to plot, for the examples in Giggly's notebooks and for your own: the tables R and
  ggplot2 ship and their documentation draws, so an example reads as it does there.

  Each dataset is a keyword list of columns, in the dataset's own order, which `Giggly.Plot.new/2`
  reads as a table, as do Explorer's `DataFrame.new/1` and Kino's data table. Whole numbers are
  integers and measurements floats; a name is a string, and a date a `Date`. A dataset is a copy of R's, kept in
  Giggly's `priv/datasets` with a header saying where it came from, and read when Giggly compiles,
  so asking for one reads nothing. Each arrives with the first notebook example that draws it.
  """

  # A dataset is data: it calls nothing, and nothing in Giggly calls it.
  use Boundary, deps: [], exports: []

  @mtcars_path Application.app_dir(:giggly, "priv/datasets/mtcars.csv")
  @external_resource @mtcars_path

  @mpg_path Application.app_dir(:giggly, "priv/datasets/mpg.csv")
  @external_resource @mpg_path

  @diamonds_path Application.app_dir(:giggly, "priv/datasets/diamonds.csv")
  @external_resource @diamonds_path

  @economics_path Application.app_dir(:giggly, "priv/datasets/economics.csv")
  @external_resource @economics_path

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

  # Each dataset's columns, its file's comment lines skipped: each named by its header, an atom
  # its table of types already holds, and read by its type.
  @parsed Map.new(
            [
              mtcars: {@mtcars_text, @mtcars_types},
              mpg: {@mpg_text, @mpg_types},
              diamonds: {@diamonds_text, @diamonds_types},
              economics: {@economics_text, @economics_types}
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
                        fn value ->
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

  # The small datasets are kept as their columns. diamonds is kept compressed, its columns in
  # Erlang's external term format, and decoded each time it is asked for: as columns it would be
  # some 18 MB held wherever this module is loaded, a release loading every module at boot, where
  # compressed it is half a megabyte, decoded in a few tens of milliseconds, with no IO either way.
  @datasets Map.take(@parsed, [:mtcars, :mpg, :economics])
  @diamonds @parsed
            |> Map.fetch!(:diamonds)
            |> :erlang.term_to_binary(compressed: 9)

  @doc """
  R's `mtcars`: fuel consumption and ten aspects of design and performance for 32 cars (1973-74
  models), from the 1974 *Motor Trend* US magazine (Henderson and Velleman, 1981). R keeps each
  car's name as a row name; here it is the first column, `model`.

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
  ggplot2's `diamonds`: the prices and other attributes of 53,940 round cut diamonds, the dataset
  ggplot2's examples reach for when a plot has too many points to see each one.

  The columns: `carat`, the weight; `cut`, the quality of the cut, from `"Fair"`, `"Good"`,
  `"Very Good"` and `"Premium"` to `"Ideal"`; `color`, from `"D"`, the best, to `"J"`, the worst;
  `clarity`, how clear, from `"I1"`, the worst, through `"SI2"`, `"SI1"`, `"VS2"`, `"VS1"`,
  `"VVS2"` and `"VVS1"` to `"IF"`, the best; `depth`, the total depth as a percentage of the
  mean width, `2 * z / (x + y)`; `table`, the width of the top relative to the widest point;
  `price`, in US dollars; and `x`, `y` and `z`, the length, width and depth in millimetres. R
  keeps `cut`, `color` and `clarity` as ordered factors; here they are their labels, which sort
  alphabetically. It is kept compressed and decoded each time it is asked for, in a few tens of
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
  @spec diamonds() :: [{atom(), [String.t() | number()]}]
  def diamonds, do: :erlang.binary_to_term(@diamonds)

  @doc """
  ggplot2's `economics`: US economic time series, one row a month from July 1967 to April 2015,
  574 in all, from the Federal Reserve Bank of St. Louis's
  [FRED](https://fred.stlouisfed.org/) database.

  The columns: `date`, the month, as a `Date` on its first day; `pce`, personal consumption
  expenditures, in billions of dollars; `pop`, the total population, in thousands; `psavert`, the
  personal savings rate; `uempmed`, the median duration of unemployment, in weeks; and `unemploy`,
  the number unemployed, in thousands. R stores every number as a double, `pop` and `unemploy`
  whole as most of their values are, so each is a float.

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
end
