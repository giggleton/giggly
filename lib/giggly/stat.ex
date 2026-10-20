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
  # The identity (`Giggly.Stat.Identity`) leaves the table as it is, as ggplot2's `geom_point()`
  # defaults `stat = "identity"`; a layer records it rather than leaving the stat out, so a layer
  # that computes nothing says so. Counting (`Giggly.Stat.Count`) counts the rows at each x, as
  # `geom_bar()` defaults `stat = "count"`, and counting at each place (`Giggly.Stat.Sum`) the rows
  # at each combination of their aesthetics, as `geom_count()` defaults `stat = "sum"`.
  #
  # A stat that computes names, in `default_mapping/1`, the computed columns its aesthetics take by
  # default, as ggplot2's `default_aes` names `after_stat(count)`: the assembly puts each into an
  # aesthetic the layer maps to nothing, and the aesthetic's guide is titled by it when no layer
  # maps the aesthetic itself. Its kind's module also names the variables a mapping's after_stat
  # can read, as ggplot2 documents them (`computed_variables/0`), and the aesthetics it consumes
  # (`dropped_aesthetics/0`), which `Giggly.Plot` checks a layer against at the call.

  # A stat is handed a layer's table and returns one, reading, summarising and building tables
  # through the data frame, and sizes what it counts at by the spacing of its positions
  # (`Giggly.Resolution`). It exports its kinds, whose structs a plot records, and nothing they
  # compute with: that is in their protocol implementations, which no boundary exports.
  use Boundary,
    deps: [Giggly.Aesthetics, Giggly.DataFrame, Giggly.Resolution],
    exports: [Count, Identity, Sum]

  alias Giggly.DataFrame

  # The layer's table `frame` after `stat` has computed on it: ggplot2's `compute_layer()`.
  @doc false
  @spec compute_layer(t(), DataFrame.t()) :: DataFrame.t()
  def compute_layer(stat, frame)

  # The computed column each aesthetic takes by default once `stat` has run, ggplot2's
  # `after_stat()` defaults: `%{y: :count}` puts the count in y. Empty for a stat that computes
  # nothing.
  @doc false
  @spec default_mapping(t()) :: %{optional(atom()) => atom()}
  def default_mapping(stat)
end
