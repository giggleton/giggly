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
  # share an x, as `geom_col()` defaults `position = "stack"`, and filling, the same kind, scales
  # each pile to reach 1, as `position = "fill"` does. Dodging (`Giggly.Position.Dodge`)
  # sets them side by side, and dodging by clusters (`Giggly.Position.Dodge2`) does so for bars
  # whose spans overlap, whatever their groups and widths. Nudging (`Giggly.Position.Nudge`) moves
  # each mark the distance its layer sets or maps, as `geom_text()` defaults `position = "nudge"`,
  # and jittering
  # (`Giggly.Position.Jitter`) a small random one, as `geom_jitter()` defaults `position =
  # "jitter"`.
  #
  # A position may read aesthetics of its own, as nudging reads `nudge_x` and `nudge_y`; it declares
  # them with their defaults, as ggplot2's position declares its `default_aes`, and the assembly
  # puts them into every row before the position runs.

  # A position is handed a layer's table and whether each axis is discrete, and returns the table,
  # reading and writing its columns through the data frame, and asks `Giggly.Resolution` how finely
  # its positions are spaced where its distances are a share of that, 1 on a discrete axis, as
  # ggplot2's positions read a mapped discrete position.
  # It exports its kinds, whose structs a plot records, and nothing they compute with: that is in
  # their protocol implementations, which no boundary exports.
  use Boundary,
    deps: [Giggly.Aesthetics, Giggly.DataFrame, Giggly.Resolution],
    exports: [Dodge, Dodge2, Identity, Jitter, Nudge, Stack]

  alias Giggly.DataFrame

  @typedoc "Whether each axis's scale is discrete or continuous."
  @type axis_kinds :: %{x: :continuous | :discrete, y: :continuous | :discrete}

  # The layer's table `frame` after `position` has moved its marks, each axis's kind in
  # `axis_kinds`: ggplot2's `compute_layer()`.
  @doc false
  @spec compute_layer(t(), DataFrame.t(), axis_kinds()) :: DataFrame.t()
  def compute_layer(position, frame, axis_kinds)

  # The aesthetics `position` reads, each with the value it takes when a layer does not set it:
  # ggplot2's `default_aes` for a position.
  @doc false
  @spec default_aesthetics(t()) :: %{optional(atom()) => term()}
  def default_aesthetics(position)
end
