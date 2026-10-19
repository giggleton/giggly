defmodule GigglyCredo.Check.PlotRunsNothing do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [roots: []],
    explanations: [
      check: """
      A plot describes and runs nothing (`.claude/rules/plot.md`). Each facet, coordinate system,
      geom, stat and position is a struct of its kind, which `Giggly.Plot` builds and whose facts
      it checks a layer against (`Geom.Point.required_aesthetics/0`); computing and drawing are the
      protocol at each family's root (`Giggly.Geom.draw_panel/4`), which the functions in `Giggly`
      reach through the assembly and rendering. `boundary` cannot keep `Plot` from calling a root
      while letting it build that root's kinds, since a boundary always exports its root module, so
      this check does: in the files it is scoped to, no module reference resolves to a root.

      This is refused:

          Geom.draw_panel(layer.geom, frame, coord, panel_params)

      while a kind's struct and its facts are what a plot writes:

          %Geom.Point{}
          Geom.Point.required_aesthetics()

      A reference counts wherever it is written: a call, a module passed as a value (which would
      close a call through a variable or `apply/3`), an `import` or a `require`, and a typespec,
      where a protocol's `t()` is any term anyway, so a field holding a kind is typed `struct()`.
      An `alias` of a root is allowed, since it names the family a kind is written through
      (`Geom.Point`), and so is the `use Boundary` declaration, whose `deps:` must name the
      families for a plot to use their kinds. Aliases are followed, grouped or renamed with `as:`.
      The check reads the code as written: a module name built at runtime is not seen.
      """,
      params: [
        roots: "The modules no reference may resolve to: the families' roots, and what draws."
      ]
    ]

  @message "A plot runs nothing: reference no family's root, only its kinds' structs and facts."

  # What an `alias` directive or a `use Boundary` declaration is replaced with as the tree is
  # walked, so the module names it holds are not reported as references.
  @walked_past {:__block__, [], []}

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)
    roots = Params.get(params, :roots, __MODULE__)

    {walked, _aliases} =
      Credo.Code.prewalk(
        source_file,
        fn node, {context, aliases} -> walk(node, context, aliases, roots) end,
        {context, %{}}
      )

    walked.issues
  end

  defp walk({:alias, _metadata, [target | options]}, context, aliases, _roots),
    do: {@walked_past, {context, remember(aliases, target, options)}}

  defp walk(
         {:use, _metadata, [{:__aliases__, _boundary_metadata, [:Boundary]} | _options]},
         context,
         aliases,
         _roots
       ),
       do: {@walked_past, {context, aliases}}

  defp walk({:__aliases__, metadata, segments} = node, context, aliases, roots) do
    if root?(segments, aliases, roots) do
      {node, {put_issue(context, issue_for(context, metadata, node)), aliases}}
    else
      {node, {context, aliases}}
    end
  end

  defp walk(node, context, aliases, _roots), do: {node, {context, aliases}}

  # `alias Giggly.Geom` and `alias Giggly.Geom, as: Drawing`: the short name stands for the whole.
  defp remember(aliases, {:__aliases__, _metadata, segments}, options) do
    case resolve(segments, aliases) do
      {:ok, full} -> Map.put(aliases, short_name(segments, options), full)
      :unknown -> aliases
    end
  end

  # `alias Giggly.{Coord, Geom}`: each child's last segment stands for the parent and the child.
  defp remember(
         aliases,
         {{:., _dot_metadata, [{:__aliases__, _parent_metadata, parent}, :{}]}, _metadata,
          children},
         _options
       ) do
    case resolve(parent, aliases) do
      {:ok, parent_full} ->
        Enum.reduce(children, aliases, fn
          {:__aliases__, _metadata, child}, remembered ->
            Map.put(remembered, List.last(child), parent_full ++ child)

          _other, remembered ->
            remembered
        end)

      :unknown ->
        aliases
    end
  end

  defp remember(aliases, _target, _options), do: aliases

  # The name an alias binds: its `as:`, or the last segment of the module it names. An alias's
  # options, when it has any, are one keyword list.
  defp short_name(segments, options) do
    as =
      options
      |> List.flatten()
      |> Keyword.get(:as)

    case as do
      {:__aliases__, _metadata, [short]} -> short
      _none -> List.last(segments)
    end
  end

  # The full name a written module name stands for: its first segment through an alias, if one
  # names it, and as written otherwise. A name opening with `__MODULE__` or a variable is unknown.
  defp resolve([first | rest] = segments, aliases) when is_atom(first) do
    case Map.fetch(aliases, first) do
      {:ok, full} -> {:ok, full ++ rest}
      :error -> {:ok, segments}
    end
  end

  defp resolve(_segments, _aliases), do: :unknown

  defp root?(segments, aliases, roots) do
    case resolve(segments, aliases) do
      {:ok, full} -> Module.concat(full) in roots
      :unknown -> false
    end
  end

  # The reference as written is what credo finds on the reported line to point at.
  defp issue_for(context, metadata, node) do
    format_issue(context,
      message: @message,
      line_no: metadata[:line],
      trigger: Macro.to_string(node)
    )
  end
end
