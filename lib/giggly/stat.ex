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
  # `geom_bar()` defaults `stat = "count"`, counting at each place (`Giggly.Stat.Sum`) the rows
  # at each combination of their aesthetics, as `geom_count()` defaults `stat = "sum"`, and
  # binning (`Giggly.Stat.Bin`) the rows in each bin of the axis, as `geom_histogram()` defaults
  # `stat = "bin"`.
  #
  # A stat that computes names, in `default_mapping/1`, the computed columns its aesthetics take by
  # default, as ggplot2's `default_aes` names `after_stat(count)`: the assembly puts each into an
  # aesthetic the layer maps to nothing, and the aesthetic's guide is titled by it when no layer
  # maps the aesthetic itself. Its kind's module also names the variables a mapping's after_stat
  # can read, as ggplot2 documents them (`computed_variables/0`), and the aesthetics it consumes
  # (`dropped_aesthetics/0`), which `Giggly.Plot` checks a layer against at the call.

  # A stat is handed a layer's table and each panel's axes and returns a table, reading,
  # summarising and building tables through the data frame, and sizes what it counts at by the
  # spacing of its positions (`Giggly.Resolution`). An axis is plain values and a function the
  # assembly builds round the panel's scale, so this boundary lists no scale. It exports its
  # kinds, whose structs a plot records, and nothing they compute with: that is in their protocol
  # implementations, which no boundary exports.
  use Boundary,
    deps: [Giggly.Aesthetics, Giggly.DataFrame, Giggly.Resolution],
    exports: [Bin, Count, Identity, Sum]

  alias Giggly.DataFrame

  @typedoc """
  One of a panel's axes as a stat reads it, ggplot2's panel scale: its extent unwidened, as
  `dimension()` gives it to a stat, in transformed positions; whether it is discrete; and a
  function putting values in data units through its transformation, as a stat transforms the
  breaks it is given.
  """
  @type axis :: %{
          limits: {number(), number()},
          discrete: boolean(),
          transform: (list() -> list())
        }

  @typedoc "Each panel's x and y axes, by panel."
  @type axes :: %{optional(term()) => %{x: axis(), y: axis()}}

  # The layer's table `frame` after `stat` has computed on it, handed each panel's axes: ggplot2's
  # `compute_layer()`, which is handed the layout's scales.
  @doc false
  @spec compute_layer(t(), DataFrame.t(), axes()) :: DataFrame.t()
  def compute_layer(stat, frame, axes)

  # The computed column each aesthetic takes by default once `stat` has run, ggplot2's
  # `after_stat()` defaults: `%{y: :count}` puts the count in y. Empty for a stat that computes
  # nothing.
  @doc false
  @spec default_mapping(t()) :: %{optional(atom()) => atom()}
  def default_mapping(stat)
end
