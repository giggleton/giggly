defmodule Giggly.Datasets do
  @moduledoc """
  Datasets to plot, for the examples in Giggly's notebooks and for your own: the tables R and
  ggplot2 ship and their documentation draws, so an example reads as it does there.

  Each dataset is a keyword list of columns, in the dataset's own order, which `Giggly.Plot.new/2`
  reads as a table, as do Explorer's `DataFrame.new/1` and Kino's data table. Whole numbers are
  integers and measurements floats; a name is a string. A dataset is a copy of R's, kept in
  Giggly's `priv/datasets` with a header saying where it came from, and read when Giggly compiles,
  so asking for one reads nothing. Each arrives with the first notebook example that draws it.
  """

  # A dataset is data: it calls nothing, and nothing in Giggly calls it.
  use Boundary, deps: [], exports: []

  @mtcars_path Application.app_dir(:giggly, "priv/datasets/mtcars.csv")
  @external_resource @mtcars_path

  @mpg_path Application.app_dir(:giggly, "priv/datasets/mpg.csv")
  @external_resource @mpg_path

  # How each of mtcars's columns is read; the file's header gives their order.
  @mtcars_types [
    model: :string,
    mpg: :float,
    cyl: :integer,
    disp: :float,
    hp: :integer,
    drat: :float,
    wt: :float,
    qsec: :float,
    vs: :integer,
    am: :integer,
    gear: :integer,
    carb: :integer
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

  # Each dataset's columns, its file's comment lines skipped: each named by its header, an atom
  # its table of types already holds, and read by its type.
  @datasets Map.new(
              [mtcars: {@mtcars_text, @mtcars_types}, mpg: {@mpg_text, @mpg_types}],
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
                      end

                    {name, Enum.map(values, read)}
                  end)

                {dataset, columns}
              end
            )

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
        cyl: 4,
        disp: 108.0,
        hp: 93,
        drat: 3.85,
        wt: 2.32,
        qsec: 18.61,
        vs: 1,
        am: 1,
        gear: 4,
        carb: 1
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
end
