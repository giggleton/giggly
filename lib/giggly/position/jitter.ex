defmodule Giggly.Position.Jitter do
  @moduledoc false

  # Jittering, ggplot2's `position_jitter()`: every mark moved a small random distance along x and
  # y, as `geom_jitter()` moves its points so that those sharing a place stand apart. Run it
  # through `Giggly.Position`.
  #
  # Each row moves by a distance from -`width` to `width` across and from -`height` to `height` up,
  # in the units of the position: a level's position on a discrete axis. An amount not given
  # (`:none`) is 0.4 of the closest spacing of the panel's positions along that axis
  # (`Giggly.Resolution`, not counting from zero), worked out panel by panel, as ggplot2's
  # `compute_jitter()` works it out, so 0.4 on a discrete axis, whatever levels a panel holds; an
  # amount of 0 moves nothing.
  #
  # The distances come from random numbers drawn from `seed` by Erlang's `exsss` algorithm, named
  # so that a change of OTP's default changes no drawing, and each panel draws afresh from the
  # seed, as ggplot2 sets its seed again for each panel. Each row in turn draws two numbers, across
  # and then up, whatever the amounts, where R draws every row's across before any row's up and
  # skips an axis whose amount is 0: R's numbers are not reproduced, so the order shows in no
  # drawing, and this way a row's distances depend only on the seed and its place among its panel's
  # rows, and an amount scales its own axis's distances without changing the other's. A draw `u`
  # from 0 to 1 becomes `-amount + 2 * amount * u`, as R's `runif()` scales one.
  #
  # Every column of the x family moves by its row's distance across, and every one of the y family
  # by its distance up, as ggplot2 moves them all, each coming out a float. A missing position
  # stays missing and an infinite one stays where it is, as IEEE arithmetic adds a distance to it.
  # Positions whose only gap is to an infinity, where R's `resolution()` is infinite and its jitter
  # sends the marks to infinity, are 1 apart, since `Giggly.Resolution` leaves an infinity out.

  @enforce_keys [:width, :height, :seed]
  defstruct @enforce_keys

  @type t :: %__MODULE__{width: :none | float(), height: :none | float(), seed: integer()}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.{Aesthetics, DataFrame, Resolution}

    # Erlang's algorithm the distances are drawn by, named so that OTP's default never changes them.
    @algorithm :exsss

    # The share of the closest spacing of a panel's positions a mark moves at most, unless given.
    @share 0.4

    # Each axis's family and the column holding each row's distance along it while the marks move.
    @distances [x: :jitter_x, y: :jitter_y]

    # Jittering reads no aesthetics of its own.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{}

    @impl Giggly.Position
    def compute_layer(%{width: width, height: height, seed: seed}, frame, axis_kinds) do
      amounts = %{
        x: amounts(frame, :x, width, axis_kinds.x),
        y: amounts(frame, :y, height, axis_kinds.y)
      }

      names = DataFrame.names(frame)

      {across, up} =
        frame
        |> DataFrame.pull(:panel)
        |> distances(amounts, seed)

      frame
      |> DataFrame.put(:jitter_x, across)
      |> DataFrame.put(:jitter_y, up)
      |> DataFrame.mutate(moves(names))
      |> DataFrame.select(Enum.map(names, fn name -> {name, name} end))
    end

    # The amount along `axis`: the one given, or, for each panel, 0.4 of the closest spacing of the
    # distinct positions it holds, 1 on a discrete axis.
    defp amounts(frame, axis, :none, kind) do
      frame
      |> DataFrame.summarise([:panel, axis], [])
      |> DataFrame.split(:panel)
      |> Map.new(fn {panel, positions} ->
        spacing =
          positions
          |> DataFrame.pull(axis)
          |> Resolution.of(zero: false, discrete: kind == :discrete)

        {panel, @share * spacing}
      end)
    end

    defp amounts(_frame, _axis, amount, _kind) when is_float(amount), do: amount

    defp amount(%{} = by_panel, panel), do: Map.fetch!(by_panel, panel)
    defp amount(amount, _panel), do: amount

    # Each row's distances across and up, in row order: two numbers drawn for each row from its
    # panel's own stream, which starts from the seed.
    defp distances(panels, amounts, seed) do
      {pairs, _streams} =
        Enum.map_reduce(panels, %{}, fn panel, streams ->
          stream = Map.get_lazy(streams, panel, fn -> :rand.seed_s(@algorithm, seed) end)
          {across, stream} = :rand.uniform_s(stream)
          {up, stream} = :rand.uniform_s(stream)
          across_amount = amount(amounts.x, panel)
          up_amount = amount(amounts.y, panel)

          {{distance(across, across_amount), distance(up, up_amount)},
           Map.put(streams, panel, stream)}
        end)

      Enum.unzip(pairs)
    end

    # R's `runif(1, -amount, amount)` for the draw `draw`: `min + (max - min) * draw`.
    defp distance(draw, amount), do: -amount + 2 * amount * draw

    # Each position column moved by its row's distance along its axis.
    defp moves(names) do
      for name <- names,
          {family, distance} <- @distances,
          Aesthetics.family(name) == family,
          do: {name, {:+, [name, distance]}}
    end
  end
end
