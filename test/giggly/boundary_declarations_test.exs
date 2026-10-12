defmodule Giggly.BoundaryDeclarationsTest do
  # Pins the architecture's weakening surface.
  #
  # Boundary declarations fail in one direction only. Too narrow fails loudly; too wide compiles in
  # silence. Every way to make the compiler enforce less is either absent from the tree or named in
  # `@sanctioned` with its reason, so widening costs an edit here, in the same diff — a visible act
  # rather than a quiet one. `Tack.BoundaryDeclarations` is the scanner; the harness tests
  # it against fabricated declarations, so this file reads only the real tree.
  use ExUnit.Case, async: true

  alias Tack.BoundaryDeclarations

  # The accepted exceptions, each with the reason it was accepted. A new entry is the decision;
  # this test failing is the prompt to make it deliberately.
  @sanctioned %{}

  @umbrella "lib/giggly.ex"

  test "no declaration disables a check except where sanctioned, with a stated reason" do
    unsanctioned =
      for path <- BoundaryDeclarations.source_files("lib"),
          {token, effect} <- BoundaryDeclarations.disabled_checks_in(path),
          not Map.has_key?(@sanctioned, {path, token}),
          do: "  #{path}: #{token} — #{effect}"

    assert unsanctioned == [],
           """
           A boundary declaration disables a compiler check without being sanctioned.

           #{Enum.join(unsanctioned, "\n")}

           This is the one kind of change nothing else will catch: it compiles clean and
           enforces less. If the exemption is right, add it to @sanctioned in this file with
           the reason — that edit is the decision, and it belongs in the same diff.
           """
  end

  test "every sanctioned exemption still exists, so the list cannot rot" do
    stale =
      for {{path, token}, _reason} <- @sanctioned,
          not sanctioned_exemption_present?(path, token),
          do: {path, token}

    assert stale == [],
           "@sanctioned names exemptions no longer in the tree: #{inspect(stale)}. Remove " <>
             "them — a standing exemption for code that no longer exists is permission " <>
             "waiting to be reused without a decision."
  end

  test "only the umbrella uses exports: :all" do
    offenders =
      for path <- BoundaryDeclarations.source_files("lib"),
          path != @umbrella,
          BoundaryDeclarations.exports_all_in?(path),
          do: path

    assert offenders == [],
           "exports: :all outside the umbrella: #{inspect(offenders)}. On a sub-boundary the " <>
             "export list is an approval gate: an explicit list fails safe (a new module is " <>
             "private until a person admits it) while :all makes it public the moment it " <>
             "compiles. List the exported modules instead (.claude/rules/dependencies.md)."
  end

  test "the boundary compiler is wired into the project" do
    assert BoundaryDeclarations.compiler_configured_in?("mix.exs"),
           "mix.exs no longer runs the boundary compiler, so every declaration in lib/ is " <>
             "inert and the architecture is unenforced. This is the single largest bypass " <>
             "and the cheapest to make by accident."
  end

  defp sanctioned_exemption_present?(path, token) do
    File.exists?(path) and
      path
      |> BoundaryDeclarations.disabled_checks_in()
      |> Enum.any?(fn {found, _effect} -> found == token end)
  end
end
