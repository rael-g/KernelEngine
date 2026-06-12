# tomlc99 (vendored)

Upstream: https://github.com/cktan/tomlc99
License: MIT (see LICENSE)
Vendored at: 2026-06-12 from `master` HEAD.

Pure-C TOML 0.5.0 parser. Used by the framework plugin to parse `.material`,
`.scene.toml`, and `.input` files without pulling toml++ (C++ template
metaprogramming) or bumping the framework plugin off the C-only doctrine
(`docs/RuntimeArchitectureV2.md` §17.1.4).

To update: replace `toml.c` + `toml.h` from upstream and rerun the framework
plugin's tests. Do not patch in-place — keep the file pristine so re-vendoring
is mechanical.
