defmodule Giggly.Aesthetics do
  @moduledoc false

  # The aesthetic vocabulary: how aesthetic names are spelled, and which of them are x or y
  # positions.
  #
  # ## Spelling
  #
  # Aesthetics are atoms named as in ggplot2, with American spelling canonical. `:color` is the name
  # every stage after the public API sees; `:colour` is accepted there and rewritten by
  # `canonicalize/1`. The vocabulary is open: a name with no alias is returned as given, and which
  # aesthetics a layer accepts is declared by its geom, stat and position. So this module decides
  # spelling, not membership.
  #
  # ## Position families
  #
  # The x scale trains on, and the coordinate system transforms, more than `:x`: `:xmin`, `:xend`,
  # `:xintercept` and the rest of the x family are all x positions, and likewise for y. `family/1`
  # classifies a name, and `counterpart/1` maps it to its partner in the other family, so a flipped
  # orientation is a renaming of columns rather than a second implementation.
  #
  # The families are ggplot2's `x_aes` and `y_aes`, and every x name has a partner in the y family.
  # The one irregular set is the boxplot hinges, where `:xlower`, `:xmiddle` and `:xupper` partner
  # `:lower`, `:middle` and `:upper`.

  # The vocabulary depends on nothing, so nothing it calls can change what a name means.
  use Boundary, deps: [], exports: []

  # Each name is written beside its partner, so neither family can gain a name without the other.
  @position_pairs [
    {:x, :y},
    {:xmin, :ymin},
    {:xmax, :ymax},
    {:xend, :yend},
    {:xintercept, :yintercept},
    {:xmin_final, :ymin_final},
    {:xmax_final, :ymax_final},
    {:xlower, :lower},
    {:xmiddle, :middle},
    {:xupper, :upper},
    {:x0, :y0}
  ]

  @x_family Enum.map(@position_pairs, fn {x_name, _y_name} -> x_name end)
  @y_family Enum.map(@position_pairs, fn {_x_name, y_name} -> y_name end)

  @counterparts @position_pairs
                |> Enum.flat_map(fn {x_name, y_name} -> [{x_name, y_name}, {y_name, x_name}] end)
                |> Map.new()

  @aliases %{colour: :color}

  @typedoc "An aesthetic name, such as `:x`, `:color` or `:linewidth`."
  @type name :: atom()

  @typedoc "The position family a name belongs to, or `:none` for every non-position aesthetic."
  @type family :: :x | :y | :none

  # The canonical spelling of an aesthetic name.
  @doc false
  @spec canonical(name()) :: name()
  def canonical(name) when is_atom(name), do: Map.get(@aliases, name, name)

  # Rewrites the keys of a mapping, or of a keyword list of fixed aesthetics, to their canonical
  # spelling. Values are untouched, and a keyword list keeps its order.
  #
  # Raises `ArgumentError` when two keys name the same aesthetic — `:color` and `:colour` together,
  # or one name twice in a keyword list — since letting either value win would draw a plot the
  # caller did not write.
  @doc false
  @spec canonicalize(%{optional(name()) => term()}) :: %{optional(name()) => term()}
  @spec canonicalize(keyword()) :: keyword()
  def canonicalize(aesthetics) when is_map(aesthetics) do
    aesthetics
    |> Map.to_list()
    |> canonical_pairs()
    |> Map.new()
  end

  def canonicalize(aesthetics) when is_list(aesthetics), do: canonical_pairs(aesthetics)

  # Rewrites each key, remembering which name first claimed each canonical aesthetic so a second
  # claim can say which two names collided.
  defp canonical_pairs(pairs) do
    {canonical_pairs, _claimed} =
      Enum.map_reduce(pairs, %{}, fn {name, value}, claimed ->
        canonical_name = canonical(name)

        case claimed do
          %{^canonical_name => earlier_name} ->
            raise ArgumentError, duplicate_message(canonical_name, earlier_name, name)

          %{} ->
            {{canonical_name, value}, Map.put(claimed, canonical_name, name)}
        end
      end)

    canonical_pairs
  end

  defp duplicate_message(canonical_name, earlier_name, name) do
    "the aesthetic #{inspect(canonical_name)} is given twice " <>
      "(as #{inspect(earlier_name)} and #{inspect(name)}); give it once"
  end

  # The position family `name` belongs to.
  @doc false
  @spec family(name()) :: family()
  def family(name) when name in @x_family, do: :x
  def family(name) when name in @y_family, do: :y
  def family(name) when is_atom(name), do: :none

  # The partner of a position name in the other family; any other name is returned as given.
  @doc false
  @spec counterpart(name()) :: name()
  def counterpart(name) when is_atom(name), do: Map.get(@counterparts, name, name)
end
