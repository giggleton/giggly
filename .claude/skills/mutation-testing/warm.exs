# Runs a commit's mutants in warm VMs: the mutation-testing skill's runner. SKILL.md, beside this
# file, says when to run it and how to read what it finds; warm.sh runs it.
#
# Each worker is one long-lived VM that loads the app and every test file once, then judges its
# share of the mutants one at a time: it compiles the mutated file over the loaded module,
# recompiles whatever read that module while compiling and now reads something different, runs
# the whole suite to its first failure, and loads the original modules back from _build. A mutant
# costs about a second there, where a fresh `mix test` in a sandbox of its own costs twenty to
# thirty, and every mutant meets every test, so no test is missed by selection.
#
# It rests on Giggly keeping no state for one mutant to leave the next: no process, application
# env, ETS table or persistent term, which the `CorePurity` check holds over lib/. A struct whose
# defaults a mutant changes is baked into every module that wrote the struct, so such a mutant is
# reported `struct_changed`, not judged. The mutants are muex's, built through its library as
# `mix muex --since SINCE --no-optimize --no-filter --files FILES` builds them, and the report is
# muex's JSON.
#
#   MIX_ENV=test mix run --no-start warm.exs slice SLICE COUNT OUT_DIR SINCE FILES
#   MIX_ENV=test mix run --no-start warm.exs report OUT_DIR SINCE FILES
#   MIX_ENV=test mix run --no-start warm.exs compare REPORT OTHER_REPORT
#
# `slice` judges the mutants whose index is SLICE modulo COUNT, appending each result to
# OUT_DIR/slice_SLICE.jsonl, and resumes from there; after a mutant runs past the timeout it
# records a timeout and exits 3, for warm.sh to start a fresh VM. `report` writes OUT_DIR/muex.json
# from the slices. `compare` sets two reports of the same commit side by side, mutant by mutant.

defmodule WarmMutation.Tracer do
  # Records the calls a module body makes while it compiles, which run then: a call with no
  # enclosing function. A capture (`&Mod.fun/2`, traced with `no_parens:` and its arity) only
  # names a function, which is looked up when it is called, at run time.
  def trace({kind, meta, module, name, arity}, %Macro.Env{function: nil} = env)
      when kind in [:remote_function, :imported_function] do
    capture? = Keyword.get(meta, :no_parens, false) and arity > 0

    if not capture? and String.starts_with?(Atom.to_string(module), "Elixir.Giggly.") do
      :ets.insert(:warm_reads, {Path.relative_to(env.file, File.cwd!()), {module, name, arity}})
    end

    :ok
  end

  def trace(_event, _environment), do: :ok
end

defmodule WarmMutation.FirstFailure do
  # An ExUnit formatter that keeps the first failure of a run: the test, or the module whose
  # setup_all failed.
  use GenServer

  def init(_options), do: {:ok, nil}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, _failures}} = test}, state) do
    record({test.tags.file, "#{inspect(test.module)}: #{test.name}"})
    {:noreply, state}
  end

  def handle_cast(
        {:module_finished, %ExUnit.TestModule{state: {:failed, _}} = test_module},
        state
      ) do
    record({test_module.file, "#{inspect(test_module.name)}: setup_all"})
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  defp record(failure) do
    Agent.update(WarmMutation.Failures, fn
      nil -> failure
      first -> first
    end)
  end
end

defmodule WarmMutation do
  @timeout_ms 60_000
  @restart_exit 3
  @equivalent_error "judged equivalent by Muex.Equivalence, so it was not run"
  @statuses %{
    "killed" => :killed,
    "survived" => :survived,
    "invalid" => :invalid,
    "timeout" => :timeout,
    "equivalent" => :equivalent,
    "no_coverage" => :no_coverage,
    "struct_changed" => :struct_changed
  }

  def main(["slice", slice, count, out_dir, since, files]) do
    slice(String.to_integer(slice), String.to_integer(count), out_dir, since, files)
  end

  def main(["report", out_dir, since, files]), do: report(out_dir, since, files)
  def main(["compare", report, other_report]), do: compare(report, other_report)

  # -- The mutants ------------------------------------------------------------------------------

  # The mutants muex would run, in its order, each with its index, and those its equivalence rules
  # judge without running, as `Muex.run/1` builds them.
  defp mutants(since, files) do
    root = File.cwd!()

    {:ok, config} =
      Muex.Config.from_args(["--since", since, "--no-optimize", "--no-filter", "--files", files])

    {:ok, changed} = Muex.GitDiff.changed_since(since, cd: root)
    {:ok, loaded} = Muex.Loader.load_all(config.files, config.language)

    entries =
      loaded
      |> Enum.map(fn file -> %{file | path: Path.relative_to(Path.expand(file.path), root)} end)
      |> Enum.filter(fn file -> Map.has_key?(changed, Path.expand(file.path)) end)

    {equivalent, judged} =
      entries
      |> Enum.flat_map(fn file ->
        context = %{file: file.path, skip_calls: config.skip_calls}
        Muex.Mutator.walk(file.ast, config.mutators, context)
      end)
      |> Enum.filter(fn mutation ->
        line = mutation.location.line
        is_integer(line) and line > 0
      end)
      |> Muex.GitDiff.filter_mutations(changed)
      |> Enum.split_with(&Muex.Equivalence.equivalent?/1)

    {config, Map.new(entries, fn file -> {file.path, file} end), Enum.with_index(judged),
     equivalent}
  end

  # -- One worker -----------------------------------------------------------------------------------

  defp slice(slice, count, out_dir, since, files) do
    File.mkdir_p!(out_dir)
    results_path = Path.join(out_dir, "slice_#{slice}.jsonl")
    done = done_indices(results_path)
    {config, entries, mutants, _equivalent} = mutants(since, files)

    mine =
      Enum.filter(mutants, fn {_mutation, index} ->
        rem(index, count) == slice and not MapSet.member?(done, index)
      end)

    log(slice, "#{length(mutants)} mutants to run, #{length(mine)} left in this slice")
    world = warm_up(slice, Map.keys(entries))

    for {mutation, index} <- mine do
      started = System.monotonic_time(:millisecond)

      task =
        Task.async(fn ->
          judge(mutation, Map.fetch!(entries, mutation.location.file), config, world)
        end)

      {status, error, test_files} =
        case Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, verdict} -> verdict
          _no_answer -> {:timeout, nil, []}
        end

      result = %{
        index: index,
        status: status,
        error: error,
        test_files: test_files,
        duration_ms: System.monotonic_time(:millisecond) - started
      }

      File.write!(results_path, Jason.encode!(result) <> "\n", [:append])

      if status == :timeout do
        log(slice, "mutant #{index} timed out; a fresh VM carries on")
        System.halt(@restart_exit)
      end
    end

    log(slice, "done")
  end

  defp done_indices(results_path) do
    if File.exists?(results_path) do
      results_path
      |> File.stream!()
      |> MapSet.new(fn line -> Jason.decode!(line)["index"] end)
    else
      MapSet.new()
    end
  end

  defp log(slice, message), do: IO.puts(:stderr, "[warm #{slice}] #{message}")

  # Loads the tests, learns what reads what while compiling, checks the suite passes, and finds
  # the lines of the mutated files no test runs.
  defp warm_up(slice, mutated_files) do
    root = File.cwd!()
    Code.put_compiler_option(:ignore_module_conflict, true)
    :ets.new(:warm_reads, [:public, :named_table, :bag])
    {:ok, _agent} = Agent.start_link(fn -> nil end, name: WarmMutation.Failures)

    app_modules = Application.spec(:giggly, :modules)

    file_modules =
      Enum.group_by(app_modules, fn module ->
        Path.relative_to(to_string(module.__info__(:compile)[:source]), root)
      end)

    # The lib files xref says read another module while compiling, compiled again under the tracer
    # to learn what they read, then loaded back from _build.
    Code.put_compiler_option(:tracers, [WarmMutation.Tracer])
    reader_files = compile_time_readers()

    for file <- reader_files do
      {:ok, _modules} = compile_quietly(fn -> Code.compile_file(file) end)
      load_built(Map.get(file_modules, file, []))
    end

    # The tests, loaded once, started as test/test_helper.exs starts them; the match stops the run
    # if the helper ever does more, which this would then have to do too.
    "ExUnit.start()\n" = File.read!("test/test_helper.exs")
    ExUnit.start(autorun: false, formatters: [WarmMutation.FirstFailure], max_failures: 1)
    test_files = Enum.map(Muex.Config.expand_test_paths(["test"]), &Path.relative_to_cwd/1)
    {:ok, loaded_modules, _warnings} = Kernel.ParallelCompiler.require(test_files)
    Code.put_compiler_option(:tracers, [])

    reads =
      :warm_reads
      |> :ets.tab2list()
      |> Enum.group_by(fn {file, _read} -> file end, fn {_file, read} -> read end)
      |> Map.new(fn {file, file_reads} -> {file, Enum.uniq(file_reads)} end)

    module_files =
      for {file, modules} <- file_modules, module <- modules, into: %{}, do: {module, file}

    world = %{
      root: root,
      app_modules: app_modules,
      file_modules: file_modules,
      test_files: test_files,
      test_modules:
        Enum.filter(loaded_modules, fn module -> function_exported?(module, :__ex_unit__, 1) end),
      reads: reads,
      original_values:
        Map.new(reads, fn {file, file_reads} -> {file, Enum.map(file_reads, &value/1)} end),
      lib_readers: Enum.filter(Map.keys(reads), fn file -> String.starts_with?(file, "lib/") end),
      test_readers:
        Enum.filter(Map.keys(reads), fn file -> String.starts_with?(file, "test/") end)
    }

    world = Map.put(world, :reach, reach(world, module_files))

    for {file, file_reads} <- reads do
      log(slice, "#{file} reads while compiling: #{inspect(file_reads)}")
    end

    {%{failures: 0} = baseline, nil} = run_suite(world)
    log(slice, "baseline: #{baseline.total} tests, no failures")

    world =
      Map.merge(world, %{
        baseline_total: baseline.total,
        line_calls: line_calls(world, mutated_files)
      })

    log(
      slice,
      "#{Enum.count(world.line_calls, fn {_line, calls} -> calls == 0 end)} lines no test runs"
    )

    world
  end

  defp compile_time_readers do
    {graph, 0} =
      System.cmd("mix", ["xref", "graph", "--label", "compile"], env: [{"MIX_ENV", "test"}])

    graph
    |> String.split("\n")
    |> Enum.filter(fn line -> String.starts_with?(line, "lib/") end)
    |> Enum.map(&String.trim/1)
  end

  # Every lib file a test file's compile-time reads can reach, from xref: the files of the modules
  # it reads and everything those depend on. A mutant touching none of them leaves it as it is.
  defp reach(world, module_files) do
    Map.new(world.test_readers, fn file ->
      sources =
        world.reads
        |> Map.fetch!(file)
        |> Enum.map(fn {module, _name, _arity} -> Map.fetch!(module_files, module) end)
        |> Enum.uniq()

      reached =
        Enum.flat_map(sources, fn source ->
          {graph, 0} =
            System.cmd("mix", ["xref", "graph", "--source", source], env: [{"MIX_ENV", "test"}])

          [source | List.flatten(Regex.scan(~r{lib/[\w/]+\.ex}, graph))]
        end)

      {file, MapSet.new(reached)}
    end)
  end

  # What a zero-arity read gives now; a read with arguments cannot be asked again, so its reader
  # is recompiled for every mutant that reaches it.
  defp value({module, name, 0}) do
    {:value, apply(module, name, [])}
  rescue
    _error -> :raised
  catch
    _kind, _reason -> :raised
  end

  defp value(_read), do: :cannot

  defp stale?(world, file) do
    values = Enum.map(Map.fetch!(world.reads, file), &value/1)
    :cannot in values or values != Map.fetch!(world.original_values, file)
  end

  # Calls per line of the mutated files' modules over one run of the suite, as muex's coverage
  # finds them: a line with no calls is run by no test; a line coverage holds nothing for (a later
  # line of a multi-line expression) is judged like any other.
  defp line_calls(world, mutated_files) do
    modules = Enum.flat_map(mutated_files, fn file -> Map.get(world.file_modules, file, []) end)
    {:ok, _cover} = :cover.start()
    for module <- modules, do: {:ok, ^module} = :cover.compile_beam(module)
    {%{failures: 0}, nil} = run_suite(world)

    calls =
      for module <- modules,
          {:ok, rows} <- [:cover.analyse(module, :calls, :line)],
          {{^module, line}, line_count} <- rows,
          line > 0,
          reduce: %{} do
        acc ->
          file = Path.relative_to(to_string(module.__info__(:compile)[:source]), world.root)
          Map.update(acc, {file, line}, line_count, fn earlier -> earlier + line_count end)
      end

    :cover.stop()
    load_built(modules)
    {%{failures: 0}, nil} = run_suite(world)
    calls
  end

  defp run_suite(world) do
    Agent.update(WarmMutation.Failures, fn _earlier -> nil end)
    result = ExUnit.run(world.test_modules)
    {result, Agent.get(WarmMutation.Failures, fn failure -> failure end)}
  end

  defp compile_quietly(compile) do
    {result, _diagnostics} =
      Code.with_diagnostics([log: false], fn ->
        try do
          {:ok, compile.()}
        rescue
          error -> {:error, Exception.message(error)}
        end
      end)

    result
  end

  defp load_built(modules) do
    for module <- modules do
      :code.purge(module)
      {:module, ^module} = :code.load_file(module)
    end
  end

  # Puts back what a mutant changed: the modules from _build, a module the mutant added deleted,
  # and the test files compiled again from their source.
  defp restore(world, modules, test_files) do
    for module <- modules do
      :code.purge(module)

      if module in world.app_modules do
        {:module, ^module} = :code.load_file(module)
      else
        :code.delete(module)
        :code.purge(module)
      end
    end

    for file <- test_files,
        do: {:ok, _modules} = compile_quietly(fn -> Code.compile_file(file) end)
  end

  # -- One mutant -----------------------------------------------------------------------------------

  defp judge(mutation, entry, config, world) do
    calls = Map.get(world.line_calls, {entry.path, mutation.location.line})

    case {calls, Muex.Compiler.compile_to_source(mutation, entry, config.language)} do
      {0, _source} ->
        {:no_coverage, "no test runs this line", []}

      {_calls, {:error, reason}} ->
        {:invalid, inspect(reason), []}

      {_calls, {:ok, source}} ->
        if Muex.Tce.equivalent_source?(entry.ast, source) do
          {:equivalent, "compiles to the same bytecode as the original (TCE)", []}
        else
          judge_source(source, entry, world)
        end
    end
  end

  defp judge_source(source, entry, world) do
    originals = Map.get(world.file_modules, entry.path, [])
    structs_before = structs(originals)

    case compile_quietly(fn -> Code.compile_string(source, Path.join(world.root, entry.path)) end) do
      {:error, message} ->
        restore(world, originals, [])
        {:invalid, message, []}

      {:ok, compiled} ->
        mutated = Enum.uniq(originals ++ Enum.map(compiled, fn {module, _binary} -> module end))

        if structs(originals) != structs_before do
          restore(world, mutated, [])
          {:struct_changed, "changes a struct's fields or defaults; judge it by hand", []}
        else
          judge_readers(entry, world, mutated)
        end
    end
  end

  defp structs(modules) do
    for module <- modules, function_exported?(module, :__struct__, 0), into: %{} do
      {module, module.__struct__()}
    end
  end

  # Recompiles each lib reader whose reads the mutant changed, until none changes; a reader that no
  # longer compiles makes the mutant invalid, as a sandbox's compile would.
  defp judge_readers(entry, world, mutated) do
    case recompile_readers(world, mutated, MapSet.new()) do
      {:invalid, message, touched} ->
        restore(world, touched, [])
        {:invalid, message, []}

      {:ok, touched, recompiled} ->
        touched_files = MapSet.put(recompiled, entry.path)

        stale_tests =
          Enum.filter(world.test_readers, fn file ->
            not MapSet.disjoint?(Map.fetch!(world.reach, file), touched_files)
          end)

        verdict = judge_tests(world, stale_tests)
        restore(world, touched, stale_tests)
        verdict
    end
  end

  defp recompile_readers(world, touched, recompiled) do
    stale =
      Enum.find(world.lib_readers, fn file ->
        not MapSet.member?(recompiled, file) and stale?(world, file)
      end)

    case stale do
      nil ->
        {:ok, touched, recompiled}

      file ->
        touched = Enum.uniq(touched ++ Map.get(world.file_modules, file, []))

        case compile_quietly(fn -> Code.compile_file(file) end) do
          {:ok, _modules} -> recompile_readers(world, touched, MapSet.put(recompiled, file))
          {:error, message} -> {:invalid, "#{file}: #{message}", touched}
        end
    end
  end

  # A test file that cannot load because the code it calls while compiling raised has caught the
  # mutant, as a failing test would.
  defp judge_tests(world, stale_tests) do
    load_failure =
      Enum.find_value(stale_tests, fn file ->
        case compile_quietly(fn -> Code.compile_file(file) end) do
          {:ok, _modules} -> nil
          {:error, message} -> {:killed, "killed by: #{file} failed to load: #{message}", [file]}
        end
      end)

    load_failure || run_verdict(world)
  end

  defp run_verdict(world) do
    case run_suite(world) do
      {%{failures: 0, total: total}, nil} when total == world.baseline_total ->
        {:survived, nil, world.test_files}

      {%{failures: 0, total: total}, nil} ->
        {:survived, "only #{total} of #{world.baseline_total} tests ran", world.test_files}

      {_result, {file, test}} ->
        {:killed, "killed by: #{test}", [Path.relative_to(file, world.root)]}

      {result, nil} ->
        {:killed, "killed by: #{result.failures} failures, none recorded", []}
    end
  end

  # -- The report -------------------------------------------------------------------------------------

  defp report(out_dir, since, files) do
    {_config, _entries, mutants, equivalent} = mutants(since, files)

    records =
      out_dir
      |> Path.join("slice_*.jsonl")
      |> Path.wildcard()
      |> Enum.flat_map(fn path -> path |> File.stream!() |> Enum.map(&Jason.decode!/1) end)
      |> Map.new(fn record -> {record["index"], record} end)

    missing = Enum.reject(mutants, fn {_mutation, index} -> Map.has_key?(records, index) end)
    if missing != [], do: raise("#{length(missing)} mutants have no result in #{out_dir}")

    judged =
      Enum.map(mutants, fn {mutation, index} ->
        record = Map.fetch!(records, index)

        %{
          mutation: mutation,
          result: Map.fetch!(@statuses, record["status"]),
          duration_ms: record["duration_ms"],
          error: record["error"],
          test_files: record["test_files"]
        }
      end)

    unrun =
      Enum.map(equivalent, fn mutation ->
        %{
          mutation: mutation,
          result: :equivalent,
          duration_ms: 0,
          error: @equivalent_error,
          test_files: []
        }
      end)

    results = judged ++ unrun
    path = Path.join(out_dir, "muex.json")
    :ok = Muex.Reporter.Json.generate(results, output_file: path)
    IO.puts("#{Muex.Reporter.summary_line(results)}. Report: #{path}")

    struct_changed = Enum.count(results, fn result -> result.result == :struct_changed end)
    if struct_changed > 0, do: IO.puts("#{struct_changed} changed a struct and were not judged")
  end

  # -- Two reports side by side -----------------------------------------------------------------------

  # Mutants are matched by file, line, mutator and description. Several can share that key (two
  # equal literals on one line), so each key's statuses are compared as sorted lists.
  defp compare(report, other_report) do
    first = statuses_by_key(report)
    second = statuses_by_key(other_report)
    keys = Enum.sort(Enum.uniq(Map.keys(first) ++ Map.keys(second)))

    pairs =
      keys
      |> Enum.flat_map(fn key ->
        first_statuses = Map.get(first, key, [])
        second_statuses = Map.get(second, key, [])

        if length(first_statuses) == length(second_statuses),
          do: Enum.zip(first_statuses, second_statuses),
          else: []
      end)
      |> Enum.frequencies()

    IO.puts("#{report} -> #{other_report}")

    for {{first_status, second_status}, number} <- Enum.sort(pairs) do
      marker = if first_status == second_status, do: "", else: "   <-- differs"

      IO.puts(
        "  #{String.pad_trailing(first_status, 14)} -> #{String.pad_trailing(second_status, 14)} #{number}#{marker}"
      )
    end

    disagreements =
      Enum.reject(keys, fn key -> Map.get(first, key, []) == Map.get(second, key, []) end)

    IO.puts("\n#{length(disagreements)} keys disagree")

    for {file, line, mutator, description} = key <- disagreements do
      IO.puts(
        "  #{file}:#{line} #{mutator} #{inspect(description)}: " <>
          "#{inspect(Map.get(first, key, []))} -> #{inspect(Map.get(second, key, []))}"
      )
    end
  end

  defp statuses_by_key(report) do
    report
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("mutations")
    |> Enum.group_by(
      fn mutation ->
        location = mutation["location"]
        {location["file"], location["line"], mutation["mutator"], mutation["description"]}
      end,
      fn mutation -> mutation["status"] end
    )
    |> Map.new(fn {key, statuses} -> {key, Enum.sort(statuses)} end)
  end
end

WarmMutation.main(System.argv())
