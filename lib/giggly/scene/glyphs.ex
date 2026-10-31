defmodule Giggly.Scene.Glyphs do
  @moduledoc false

  # The outlines a text's labels are drawn with, where its font gives them: `runs` holds each
  # label's glyphs, in the order of the text's labels, each `{outline, x, y}`, the glyph's place in
  # points from the label's start on its baseline, along it and up from it, and its outline in the
  # font's own units, y rising upward, which `scale` turns into points. A glyph that draws nothing,
  # such as a space, is left out of its run.
  #
  # An outline is its contours in order, each a move to its first point, then lines, quadratic and
  # cubic curves, each from where the last ended, and a close back to its start.

  @enforce_keys [:scale, :runs]
  defstruct @enforce_keys

  @type command ::
          {:move, float(), float()}
          | {:line, float(), float()}
          | {:quad, float(), float(), float(), float()}
          | {:cubic, float(), float(), float(), float(), float(), float()}
          | :close

  @type t :: %__MODULE__{
          scale: float(),
          runs: [[{[command()], float(), float()}]]
        }
end
