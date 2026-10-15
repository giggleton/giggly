defprotocol Giggly.Position do
  @moduledoc false

  # Position adjustments: where a layer's marks move to once its stat has run, as ggplot2's
  # positions stack bars, dodge them side by side or jitter points apart.
  #
  # A layer records its position as a struct of its kind, and the assembly runs it here after the
  # stat. Each position is one module holding everything about it: its struct, whose fields are the
  # position's parameters, and its computing, in a `defimpl Giggly.Position` whose first line
  # classifies it into this boundary, since boundary checks nothing a protocol implementation calls
  # until it is classified. A position is named only through this namespace
  # (`Position.Identity`), never aliased to its last segment, which other namespaces share.
  #
  # The identity (`Giggly.Position.Identity`) moves nothing, as ggplot2's `geom_point()` defaults
  # `position = "identity"`; a layer records it rather than leaving the position out, so a layer
  # whose marks stay where they are says so. Stacking (`Giggly.Position.Stack`) piles bars that
  # share an x, as `geom_col()` defaults `position = "stack"`.

  # A position is handed a layer's table and returns one, reading and writing its columns through
  # the data frame.
  # It exports its kinds, whose structs a plot records, and nothing they compute with: that is in
  # their protocol implementations, which no boundary exports.
  use Boundary, deps: [Giggly.DataFrame], exports: [Dodge, Identity, Stack]

  alias Giggly.DataFrame

  # The layer's table `frame` after `position` has moved its marks: ggplot2's `compute_layer()`.
  @doc false
  @spec compute_layer(t(), DataFrame.t()) :: DataFrame.t()
  def compute_layer(position, frame)
end
