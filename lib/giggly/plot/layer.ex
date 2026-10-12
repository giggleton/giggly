defmodule Giggly.Plot.Layer do
  @moduledoc """
  One layer of a plot: a geom, and the mapping the layer adds to the plot's.

  A layer is built by a `Giggly.Plot` function such as `Giggly.Plot.geom_point/2`, which has
  already checked it, so its fields hold what that function resolved: `mapping` names each column
  by its string name in the plot's data. A layer's mapping is laid over the plot's when the plot is
  assembled, and holds only the aesthetics the layer adds or remaps.
  """

  alias Giggly.Plot

  @enforce_keys [:geom, :mapping]
  defstruct @enforce_keys

  @typedoc "What the layer draws."
  @type geom :: :point

  @type t :: %__MODULE__{geom: geom(), mapping: Plot.mapping()}
end
