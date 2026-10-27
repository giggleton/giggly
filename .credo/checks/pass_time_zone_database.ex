defmodule GigglyCredo.Check.PassTimeZoneDatabase do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      The pipeline reads no application config (CLAUDE.md, Approach & architecture), and every
      `DateTime` function that works in a time zone takes the time zone database as its last
      argument, defaulting to `Calendar.get_time_zone_database/0`, which reads
      `Application.fetch_env!(:elixir, :time_zone_database)`. Elixir evaluates a default argument
      on every call that leaves it out, even for UTC, so such a call reads config where
      `Tack.Credo.Check.CorePurity`, which sees only calls written out, cannot see it.

      This should be refactored:

          DateTime.shift_zone(datetime, zone)

      to look like this:

          DateTime.shift_zone(datetime, zone, database)

      passing the database a scale carries, or `Calendar.UTCOnlyTimeZoneDatabase`, the standard
      library's, which knows UTC alone.

      The check reads the code as written: a call through an alias of `DateTime` under another
      name, or an `import DateTime`, is not seen.
      """
    ]

  # Each function that takes its time zone database from config, by module and the arities that
  # leave the database out, from Elixir 1.20.4's `DateTime`.
  @defaulting %{
    DateTime: %{
      new: [2, 3],
      new!: [2, 3],
      from_naive: [2],
      from_naive!: [2],
      shift_zone: [2],
      shift_zone!: [2],
      now: [1],
      now!: [1],
      add: [2, 3],
      shift: [2]
    },
    Calendar: %{get_time_zone_database: [0]}
  }

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)
    walked = Credo.Code.prewalk(source_file, fn node, context -> walk(node, context) end, context)
    walked.issues
  end

  # A call piped into: its arity is one more than its arguments, and it is replaced by its
  # arguments alone, so they are still read and the call is not read again unpiped.
  defp walk(
         {:|>, metadata, [piped, {{:., _, [{:__aliases__, _, [module]}, name]}, call, args}]},
         context
       ) do
    checked = found(context, module, name, length(args) + 1, call)
    {{:|>, metadata, [piped, {:__block__, [], args}]}, checked}
  end

  # A capture, `&DateTime.shift_zone/2`, at the arity it names.
  defp walk(
         {:&, _, [{:/, _, [{{:., _, [{:__aliases__, _, [module]}, name]}, call, []}, arity]}]} =
           node,
         context
       )
       when is_integer(arity),
       do: {node, found(context, module, name, arity, call)}

  defp walk({{:., _, [{:__aliases__, _, [module]}, name]}, call, args} = node, context)
       when is_list(args),
       do: {node, found(context, module, name, length(args), call)}

  defp walk(node, context), do: {node, context}

  defp found(context, module, name, arity, metadata) do
    arities =
      @defaulting
      |> Map.get(module, %{})
      |> Map.get(name, [])

    if arity in arities,
      do: put_issue(context, issue_for(context, metadata, "#{module}.#{name}", arity)),
      else: context
  end

  defp issue_for(context, metadata, function, arity) do
    format_issue(context,
      message:
        "`#{function}/#{arity}` takes its time zone database from config; pass one, the " <>
          "scale's or `Calendar.UTCOnlyTimeZoneDatabase`.",
      line_no: metadata[:line],
      trigger: function
    )
  end
end
