defmodule Giggly.Plot.Layer do
  @moduledoc false

  # One layer of a plot: a geom, the stat and the position it is drawn with, the mapping the layer
  # adds to the plot's, and the aesthetics it sets to one value for every mark.
  #
  # A layer is built by a `Giggly.Plot` function such as `Giggly.Plot.geom_point/3`, which has
  # already checked it, so its fields hold what that function resolved: `mapping` names each column
  # by its string name in the plot's data. A layer's mapping is laid over the plot's when the plot
  # is assembled, and holds only the aesthetics the layer adds or remaps. The geom, stat and
  # position are structs of their kinds, each always given, the identity included: a layer whose
  # stat computes nothing says so. `fixed` holds the aesthetics the function's options set, by
  # canonical name, as ggplot2's `aes_params` does, and is empty when it sets none.

  alias Giggly.Plot

  @enforce_keys [:geom, :stat, :position, :mapping, :fixed]
  defstruct @enforce_keys

  @typedoc "What the layer draws: a geom's struct (`Giggly.Geom`)."
  @type geom :: struct()

  @typedoc "What the layer's table is computed into before it is drawn: a stat's struct (`Giggly.Stat`)."
  @type stat :: struct()

  @typedoc "How the layer's marks are moved once its stat has run: a position's struct (`Giggly.Position`)."
  @type position :: struct()

  @typedoc "The aesthetics a layer sets to one value for every mark, by canonical name."
  @type fixed :: %{optional(Plot.aesthetic()) => float()}

  @type t :: %__MODULE__{
          geom: geom(),
          stat: stat(),
          position: position(),
          mapping: Plot.mapping(),
          fixed: fixed()
        }
end
