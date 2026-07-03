# tomlc99 (vendored)

Upstream: https://github.com/cktan/tomlc99
License: MIT (see LICENSE)
Vendored at: 2026-07-02 from `master` HEAD.

Pure-C TOML 0.5.0 parser. Used by the `ke_configuration_toml` loader (Zig lib)
to parse `Project.toml` into a `ke_configuration` store. The Zig loader consumes
it via `@cImport("toml.h")` and compiles `toml.c` in its own `build.zig` — no
Zig-package TOML parser was 0.16-ready (mattyhall/tomlz and sam701/zig-toml both
use pre-0.16 `build.zig` APIs), so the proven C parser is vendored instead.

Contained to this module per the vendoring doctrine: this copy is independent of
the identical copy the framework plugin vendors — neither reaches into the other.

To update: replace `toml.c` + `toml.h` from upstream and rerun this module's
tests. Do not patch in-place — keep the files pristine so re-vendoring is
mechanical.
