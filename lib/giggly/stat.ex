defprotocol Giggly.Stat do
  @moduledoc false

  # Statistical transformations: what a layer's table is computed into before it is positioned and
  # drawn, as ggplot2's stats compute counts, bins or summaries from the rows they are given.
  #
  # A layer records its stat as a struct of its kind, and the assembly runs it here once the
  # position scales have mapped the layer's x and y columns, so a stat computes on positions: a
  # discrete value is its level's position. Each stat is one module holding everything about it:
  # its struct, whose fields are the stat's parameters, and its computing, in a
  # `defimpl Giggly.Stat` whose first line classifies it into this boundary, since boundary checks
  # nothing a protocol implementation calls until it is classified. A stat is named only through
  # this namespace (`Stat.Identity`), never aliased to its last segment, which other namespaces
  # share.
  #
  # There is one stat so far, the identity (`Giggly.Stat.Identity`), which leaves the table as it
  # is, as ggplot2's `geom_point()` defaults `stat = "identity"`. A layer records it rather than
  # leaving the stat out, so a layer that computes nothing says so.

  # A stat is handed a layer's table and returns one. It names the data frame's type in its
  # specs, which boundary does not check, and lists nothing because nothing here calls the data
  # frame yet.
  # It exports its kinds, whose structs a plot records, and nothing they compute with: that is in
  # their protocol implementations, which no boundary exports.
  use Boundary, deps: [], exports: [Identity]

  alias Giggly.DataFrame

  # The layer's table `frame` after `stat` has computed on it: ggplot2's `compute_layer()`.
  @doc false
  @spec compute_layer(t(), DataFrame.t()) :: DataFrame.t()
  def compute_layer(stat, frame)
end
