defmodule Giggly do
  @moduledoc """
  Giggly is a grammar-of-graphics plotting library for Elixir, modelled on ggplot2.

  This module is the root of the `Giggly` namespace. The public API — building a plot spec,
  building it into per-panel layer tables and trained scales, and rendering it to SVG — will be
  exposed from here as it is written.
  """

  # The umbrella: every context, the infrastructure and (until a pure core is carved out) the
  # domain rules. `exports: :all` is the pragmatic start and is legal only here; the hook denies
  # it on any sub-boundary. Narrow it with `{:all, except: [...]}` as rules worth a compiler
  # check appear — a module nothing outside Giggly may call.
  use Boundary, exports: :all
end
