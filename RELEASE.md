# Releasing Giggly

A release goes in one order, and nothing but this file enforces it. The documentation links each
function to its source at the tag `v<version>` (`source_ref` in `mix.exs`), so the tag is pushed
before the package is published.

Publishing to Hex needs the maintainer's Hex keys; it is never done by an agent.

1. **Set the version.** In `mix.exs`, set `@version` to the release, say `"0.1.0"`, and commit it.

2. **See the gate pass**: `mix quality` locally, and CI on that commit.

3. **Check the package.**

   ```bash
   mix hex.build --unpack
   ```

   The unpacked package should hold `lib/`, `priv/datasets/` and `priv/fonts/` (both read when
   the package compiles), `mix.exs`, `.formatter.exs`, `README.md`, `LICENSE` and
   `THIRD_PARTY_NOTICES.md`, and nothing else.

4. **Tag and push.**

   ```bash
   git tag v0.1.0
   git push origin main v0.1.0
   ```

5. **Publish.**

   ```bash
   mix hex.publish
   ```
