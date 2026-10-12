defmodule Giggly.Stat do
  @moduledoc """
  Statistical transformations: what a layer's table is computed into before it is positioned and
  drawn, as ggplot2's stats compute counts, bins or summaries from the rows they are given.

  A layer records its stat by name, and the assembly runs it here once the position scales have
  mapped the layer's x and y columns, so a stat computes on positions: a discrete value is its
  level's position. Each stat is a module implementing this behaviour, named only through this
  namespace (`Stat.Identity`), never aliased to its last segment, which other namespaces share.

  There is one stat so far, the identity (`Giggly.Stat.Identity`), which leaves the table as it is,
  as ggplot2's `geom_point()` defaults `stat = "identity"`. A layer names it rather than leaving the
  stat out, so a layer that computes nothing says so.
  """

  # A stat is handed a layer's table and returns one. It names the data frame's type in its specs,
  # and lists nothing because nothing here calls the data frame yet.
  use Boundary, deps: [], exports: []

  alias Giggly.{DataFrame, Stat}

  @typedoc "A stat's name, as a layer records it."
  @type name :: :identity

  @doc "The layer's table after the stat has computed on it: ggplot2's `compute_layer()`."
  @callback compute_layer(DataFrame.t()) :: DataFrame.t()

  @doc """
  The layer's table `frame` after the stat named `name` has computed on it.
  """
  @spec compute(DataFrame.t(), name()) :: DataFrame.t()
  def compute(frame, :identity), do: Stat.Identity.compute_layer(frame)
end
