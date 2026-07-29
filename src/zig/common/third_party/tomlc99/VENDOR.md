# tomlc99 (vendored)

Upstream: https://github.com/cktan/tomlc99
License: MIT (see LICENSE)
Vendored at: 2026-06-12 from `master` HEAD.

Pure-C TOML 0.5.0 parser. Single shared copy consumed by every plugin that
parses TOML — the framework plugin (`.material`, `.scene.toml`, `.input`) and
`ke_configuration_toml` — without pulling toml++ (C++ template metaprogramming)
or bumping those plugins off the C-only doctrine
(`docs/RuntimeArchitectureV2.md` §17.1.4). Each consuming plugin's `build.zig`
compiles `toml.c` from this one directory; the path is threaded in by the root
`build.zig` as `-Dtomlc99-dir`, and each plugin falls back to this in-tree
location when built standalone.

To update: replace `toml.c` + `toml.h` from upstream and rerun the consuming
plugins' tests. Do not patch in-place — keep the file pristine so re-vendoring
is mechanical.
