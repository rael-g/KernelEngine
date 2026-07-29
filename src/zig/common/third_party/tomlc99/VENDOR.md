# tomlc99 (vendored)

Upstream: https://github.com/cktan/tomlc99
License: MIT (see LICENSE)
Vendored at: 2026-06-12 from `master` HEAD.

Pure-C TOML 0.5.0 parser. Single shared copy consumed by every plugin that
parses TOML — the framework plugin (`.material`, `.scene.toml`, `.input`) and
`ke_configuration_toml` — without pulling toml++ (C++ template metaprogramming)
or bumping those plugins off the C-only doctrine
(`docs/RuntimeArchitectureV2.md` §17.1.4). Each consuming plugin's `build.zig`
compiles `toml.c` (and, on Windows, `ke_strtod_shim.c`) from this one directory;
the path is threaded in by the root `build.zig` as `-Dtomlc99-dir`.

To update: replace `toml.c` + `toml.h` from upstream and rerun the consuming
plugins' tests, then re-apply the local modification below.

## Local modifications

- **`toml.c`, after the `#include` block (Windows only):** a guarded
  `#define strtod ke_toml_strtod` / `#define strtoll ke_toml_strtoll`. Upstream
  parses numbers with the platform `strtod`/`strtoll`; on Windows the mingw libc
  Zig bundles routes `strtod` through gdtoa, whose first call registers an
  `atexit()` cleanup into an onexit table that mingw's `DllMainCRTStartup` never
  initializes inside a Zig-built DLL — a write into uninitialized memory that
  corrupts the heap (tolerated by glibc on Linux, faults on Windows' UCRT). The
  shims (`ke_strtod_shim.c`, compiled beside `toml.c` on Windows) delegate to
  the fully-initialized UCRT `strtod`/`_strtoi64` in `ucrtbase.dll`. Non-Windows
  builds are untouched (the shim file is `#ifdef _WIN32`-guarded and not
  compiled elsewhere).
