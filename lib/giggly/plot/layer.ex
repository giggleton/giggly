defmodule Giggly.Plot.Layer do
  @moduledoc """
  One layer of a plot: a geom, the stat and the position it is drawn with, and the mapping the
  layer adds to the plot's.

  A layer is built by a `Giggly.Plot` function such as `Giggly.Plot.geom_point/2`, which has
  already checked it, so its fields hold what that function resolved: `mapping` names each column
  by its string name in the plot's data. A layer's mapping is laid over the plot's when the plot is
  assembled, and holds only the aesthetics the layer adds or remaps. The stat and position are
  names, each always given, the identity included: a layer whose stat computes nothing says so.
  """

  alias Giggly.Plot

  @enforce_keys [:geom, :stat, :position, :mapping]
  defstruct @enforce_keys

  @typedoc "What the layer draws."
  @type geom :: :point

  @typedoc "What the layer's table is computed into before it is drawn (`Giggly.Stat`)."
  @type stat :: :identity

  @typedoc "How the layer's marks are moved once its stat has run (`Giggly.Position`)."
  @type position :: :identity

  @type t :: %__MODULE__{
          geom: geom(),
          stat: stat(),
          position: position(),
          mapping: Plot.mapping()
        }
end
