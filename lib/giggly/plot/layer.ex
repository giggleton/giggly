defmodule Giggly.Plot.Layer do
  @moduledoc false

  # One layer of a plot: a geom, the stat and the position it is drawn with, the table it draws if
  # it has one of its own, the mapping the layer adds to the plot's, and the aesthetics it sets to
  # one value for every mark.
  #
  # A layer is built by a `Giggly.Plot` function such as `Giggly.Plot.geom_point/3`, which has
  # already checked it, so its fields hold what that function resolved: `data` is the table its
  # `data:` option gave, read into a `Giggly.DataFrame`, or `:none` when it draws the plot's data,
  # and `mapping` names each column by its string name in the table the layer draws. A layer's
  # mapping is laid over the plot's when the plot is assembled, and holds only the aesthetics the
  # layer adds or remaps. The geom, stat and position are structs of their kinds, each always given,
  # the identity included: a layer whose stat computes nothing says so. `fixed` holds the aesthetics
  # the function's options set, by canonical name, as ggplot2's `aes_params` does, and is empty when
  # it sets none. `accepted` lists the aesthetics the layer can use, its geom's and its stat's,
  # which its own mapping is checked against; an aesthetic it takes from the plot's mapping that it
  # cannot use rides along unused, as in ggplot2, and the layer draws in a legend only for those it
  # accepts.

  alias Giggly.{DataFrame, Plot}

  @enforce_keys [:geom, :stat, :position, :data, :mapping, :fixed, :accepted]
  defstruct @enforce_keys

  @typedoc "What the layer draws: a geom's struct (`Giggly.Geom`)."
  @type geom :: struct()

  @typedoc "What the layer's table is computed into before it is drawn: a stat's struct (`Giggly.Stat`)."
  @type stat :: struct()

  @typedoc "How the layer's marks are moved once its stat has run: a position's struct (`Giggly.Position`)."
  @type position :: struct()

  @typedoc """
  The aesthetics a layer sets to one value for every mark, by canonical name: a number, such as an
  alpha or a line's width, or a colour, uppercase hex or `:none`.
  """
  @type fixed :: %{optional(Plot.aesthetic()) => float() | String.t() | :none}

  @type t :: %__MODULE__{
          geom: geom(),
          stat: stat(),
          position: position(),
          data: DataFrame.t() | :none,
          mapping: Plot.mapping(),
          fixed: fixed(),
          accepted: [Plot.aesthetic()]
        }
end
