defmodule Giggly.Position do
  @moduledoc """
  Position adjustments: where a layer's marks move to once its stat has run, as ggplot2's
  positions stack bars, dodge them side by side or jitter points apart.

  A layer records its position by name, and the assembly runs it here after the stat. Each
  position is a module implementing this behaviour, named only through this namespace
  (`Position.Identity`), never aliased to its last segment, which other namespaces share.

  There is one position so far, the identity (`Giggly.Position.Identity`), which moves nothing, as
  ggplot2's `geom_point()` defaults `position = "identity"`. A layer names it rather than leaving
  the position out, so a layer whose marks stay where they are says so.
  """

  # A position is handed a layer's table and returns one. It names the data frame's type in its
  # specs, and lists nothing because nothing here calls the data frame yet.
  use Boundary, deps: [], exports: []

  alias Giggly.{DataFrame, Position}

  @typedoc "A position's name, as a layer records it."
  @type name :: :identity

  @doc "The layer's table with its marks moved: ggplot2's `compute_layer()`."
  @callback compute_layer(DataFrame.t()) :: DataFrame.t()

  @doc """
  The layer's table `frame` after the position named `name` has moved its marks.
  """
  @spec compute(DataFrame.t(), name()) :: DataFrame.t()
  def compute(frame, :identity), do: Position.Identity.compute_layer(frame)
end
