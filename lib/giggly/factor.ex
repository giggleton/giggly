defmodule Giggly.Factor do
  @moduledoc """
  A column whose values have levels: the values it may hold, in an order of their own, which a
  plot follows wherever it orders the column's values: on an axis, in a legend, in the groups a
  stat counts and a position stacks, and in a facet's panels.

  Put one in a table where a column would go:

      %{
        "cut" => Giggly.Factor.new(["Ideal", "Fair"], levels: ["Fair", "Good", "Ideal"]),
        "price" => [326, 327]
      }

  A factor enumerates as its values, so anything that reads a table (`Table.Reader`, Explorer's
  `DataFrame.new/1`, Kino's data table) reads the column as they are, without its levels.

  `levels:` names each level as the values hold it (`[8, 4, 6]` for numbers), and a value not
  among them is missing. Without it, the levels are the distinct values in order: numbers by
  value, dates and times by time, strings by their bytes, `false` before `true`. `ordered: true`
  marks the levels as ordered. The table refuses, when a plot reads it, levels that hold `nil`,
  that name one value twice (`4` and `4.0` are one), or whose type is not the values'.

      iex> cut = Giggly.Factor.new(["Ideal", "Fair", "Ideal"], levels: ["Fair", "Good", "Ideal"])
      iex> Enum.to_list(cut)
      ["Ideal", "Fair", "Ideal"]
      iex> plot =
      ...>   %{"cut" => cut}
      ...>   |> Giggly.Plot.new(%{x: :cut})
      ...>   |> Giggly.Plot.geom_bar()
      iex> Giggly.panel_scales(plot, 1).x.levels
      ["Fair", "Ideal"]

  A level no value holds takes no place on the axis, as `Good` takes none here.
  """

  # A column type, and its own boundary: the frame lists it, to read a factor's levels when it
  # reads a table, and so does `Giggly.Datasets`, whose tables hold factors. It checks only its
  # options' shapes; the frame types its values and levels when a plot reads it, as it types any
  # column. It lists NimbleOptions, which validates its options, and nothing else.
  use Boundary, deps: [NimbleOptions], exports: []

  @enforce_keys [:values, :levels, :ordered]
  defstruct @enforce_keys

  @typedoc """
  A factor: its values in row order, its levels, or `:default` for its distinct values in order,
  and whether the levels are ordered.
  """
  @type t :: %__MODULE__{values: list(), levels: list() | :default, ordered: boolean()}

  @schema NimbleOptions.new!(
            levels: [
              type: {:list, :any},
              doc: "The values the factor may hold, in their order."
            ],
            ordered: [
              type: :boolean,
              default: false,
              doc: "Whether the levels are ordered."
            ]
          )

  @doc """
  A factor of `values`, a list in row order.

  ## Options

  #{NimbleOptions.docs(@schema)}
  """
  @spec new(list(), keyword()) :: t()
  def new(values, options \\ []) when is_list(values) do
    validated = NimbleOptions.validate!(options, @schema)

    %__MODULE__{
      values: values,
      levels: Keyword.get(validated, :levels, :default),
      ordered: Keyword.fetch!(validated, :ordered)
    }
  end

  # A factor enumerates as its values, which it hands to the list's own enumeration.
  defimpl Enumerable do
    @impl Enumerable
    def count(%Giggly.Factor{values: values}), do: {:ok, length(values)}

    @impl Enumerable
    def member?(%Giggly.Factor{}, _value), do: {:error, __MODULE__}

    @impl Enumerable
    def slice(%Giggly.Factor{}), do: {:error, __MODULE__}

    @impl Enumerable
    def reduce(%Giggly.Factor{values: values}, accumulator, function),
      do: Enumerable.reduce(values, accumulator, function)
  end
end
