defmodule Giggly.Geom.Mark do
  @moduledoc false

  # What a geom reads from its rows to give each mark its look: the value a layer sets for every
  # mark, which the assembly puts in every row; each row's value of an aesthetic, mapped or set;
  # and a mark's colour and opacity, as ggplot2's geoms make them with `alpha()`.
  #
  # A row's alpha replaces its colour's own, and a row without one, or a table without the column,
  # keeps the colour's, which for a colour with no alpha of its own is opaque. A colour reaches a
  # geom in the spelling `Giggly.Plot` gives it, uppercase `#RRGGBB` or `#RRGGBBAA`, or `:none`,
  # R's `NA`, which draws nothing whatever the alpha, as `alpha(NA, 0.5)` is `NA`; it reaches the
  # scene as its `#RRGGBB` and an opacity, which the backend writes as svglite writes an R colour's
  # alpha.

  alias Giggly.DataFrame

  # The value the layer sets for `aesthetic`, the same in every row of `frame`, or `default` where
  # it sets none.
  @doc false
  @spec set(DataFrame.t(), atom(), term()) :: term()
  def set(frame, aesthetic, default) do
    if aesthetic in DataFrame.names(frame) do
      [value] =
        frame
        |> DataFrame.pull(aesthetic)
        |> Enum.uniq()

      value
    else
      default
    end
  end

  # Each row's value of `aesthetic` in `frame`: its column, mapped or set, or `default` in every row
  # where the table has none.
  @doc false
  @spec values(DataFrame.t(), atom(), term()) :: list()
  def values(frame, aesthetic, default) do
    if aesthetic in DataFrame.names(frame),
      do: DataFrame.pull(frame, aesthetic),
      else: List.duplicate(default, DataFrame.row_count(frame))
  end

  # Each row's opacity in its colour, one of `colors` for each row: its alpha, or the colour's own
  # where it has none or the table has no alpha.
  @doc false
  @spec opacities(DataFrame.t(), [String.t() | :none]) :: [float()]
  def opacities(frame, colors) do
    frame
    |> values(:alpha, nil)
    |> Enum.zip_with(colors, fn alpha, color -> opacity(color, alpha) end)
  end

  # A mark's opacity in `color`, from 0 to 1: its alpha, or the colour's own where it has none.
  @doc false
  @spec opacity(String.t() | :none, number() | nil | :nan) :: float()
  def opacity(:none, _alpha), do: 0.0
  def opacity(_color, alpha) when is_number(alpha), do: alpha / 1
  def opacity(color, missing) when missing in [nil, :nan], do: own_opacity(color)

  # A colour's own opacity: its alpha byte over 255, opaque for a colour without one, and none for
  # no colour.
  @doc false
  @spec own_opacity(String.t() | :none) :: float()
  def own_opacity(:none), do: 0.0
  def own_opacity(<<"#", _digits::binary-size(6)>>), do: 1.0

  def own_opacity(<<"#", _digits::binary-size(6), alpha::binary-size(2)>>),
    do: String.to_integer(alpha, 16) / 255

  # A colour's `#RRGGBB`, as a stroke or a fill is written, or `:none`.
  @doc false
  @spec hex(String.t() | :none) :: String.t() | :none
  def hex(:none), do: :none
  def hex(<<"#", _digits::binary-size(6)>> = color), do: color
  def hex(<<"#", digits::binary-size(6), _alpha::binary-size(2)>>), do: "#" <> digits
end
