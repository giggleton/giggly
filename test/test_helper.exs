# A family registered with Pica is measured from its font, so the tests that measure one run only
# where Pica is a dependency, and those of a build without it (`GIGGLY_WITHOUT_PICA=1`) only
# there. Each font is registered once, here, which the warm mutation runner also runs once.
if Code.ensure_loaded?(Pica) do
  load = fn file ->
    {:ok, font} =
      "test/fonts"
      |> Path.join(file)
      |> File.read!()
      |> Pica.load()

    font
  end

  :ok = Pica.register("Lato", plain: load.("Lato-Regular.ttf"), bold: load.("Lato-Bold.ttf"))
  ExUnit.start(exclude: [:without_pica])
else
  ExUnit.start(exclude: [:pica])
end
