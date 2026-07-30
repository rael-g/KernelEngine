# Zig Migration Plan

> **Status: PROPOSAL / DEBATE — not started.** This document captures the plan and
> the open architectural decisions for migrating KernelEngine's *implementation*
> language from C/C++ to Zig, and its *build system* from CMake+vcpkg to Zig's
> build system. Nothing here is locked. Sections marked **[DECISION — PO]** are
> open forks awaiting the Product Owner; the senior-engineer recommendation is
> stated but not yet adopted.

---

## 0. The thesis (what we are and are not changing)

**The public API stays C.** Every vtable, struct, enum and factory symbol the
engine exposes remains C-ABI, exactly as today (`src/c/kernel/include/`). The
C# binding pipeline (ClangSharp over the C headers) is **completely insulated** —
it does not care what language produced the DLL.

**Only implementations change.** The `.cpp` glue we author becomes Zig.

**[DECIDED — PO, 2026-06-17] End-state scope is pragmatic, not dogmatic.** The goal
is *not* "zero C++ at all." Use Zig where there is an excellent Zig path; keep the
C/C++ dependency (and, where unavoidable, a thin C++ shim) where there isn't.
Third-party C/C++ binaries we merely *link* (bgfx core, assimp) stay. The driver
is "get rid of CMake + author new code in Zig," not "purge every C++ object."

**Why Zig over plain C** (the original fallback):
- C-ABI export is first-class: `export fn ke_foo_create(...) callconv(.C)` →
  unmangled `ke_foo_create`, no export-macro dance, no `KE_*_EXPORT` headers.
- `extern struct` gives guaranteed C layout; vtables-of-fn-pointers are natural.
  Kills the `bool`→`ke_bool` ABI hazard class entirely (Zig `bool` is well-defined
  at the boundary and layout is explicit).
- Memory-safety affordances over C: explicit error unions, `defer`/`errdefer`,
  slices (ptr+len as one type), bounds checks in debug, no implicit UB.
- `@cImport` consumes the kernel's own C headers — the impl reads the same
  contract the bindings read. Single source of truth, zero duplication.
- `zig cc` is a drop-in Clang for C and C++ → the existing tree keeps building
  during the entire transition. This is what makes the migration incremental
  instead of big-bang.

**Why the implementations being C++ today buys nothing:** the engine boundary is
C vtables. Our C++ plugins are thin translators (a vtable call → a library call).
At that boundary C++ contributes name-mangling friction, STL types that must not
leak, and the `ke_bool` workaround — and contributes no abstraction we keep.

---

## 1. Current build topology (the contract Zig must reproduce)

Grounded in the repo as of branch `feat/kernel-v2`:

- **Generator/toolchain:** Ninja + Clang/Clang++, vcpkg toolchain file
  (`CMakePresets.json`). Triplets: `x64-windows-static-md` (Win),
  `x64-linux` (Linux). Host triplet `x64-windows` for bgfx tools.
- **vcpkg manifest** (`vcpkg.json`): spdlog, glfw3, glad, stb, glm, box2d, **bgfx**
  (+`tools` feature, host), **assimp**, gtest, enkits, miniaudio, tomlplusplus, flecs.
- **~40 internal targets** (`CMakeLists.txt`): per-domain kernel libs
  (`ke_allocator`, `ke_logger`, `ke_runtime`, `ke_framework`, …) + C++ plugins
  (`ke_window_glfw`, `ke_render_bgfx`, `ke_asset_assimp`, …). Recent commit split
  `ke_kernel` into per-domain **SHARED** DLLs; consumers link domain targets
  directly (no `ke_kernel` meta-target).
- **Per-target shape** (e.g. `src/c/runtime/CMakeLists.txt`,
  `src/cpp/window/glfw/CMakeLists.txt`): one `add_library`, `PUBLIC` include dir
  = `include/`, `PRIVATE` impl deps, `KE_<DOMAIN>_EXPORT` define on shared / 
  `KE_<DOMAIN>_STATIC` on static, an `install(TARGETS … RUNTIME DESTINATION bin)`.
- **Output contract C# depends on** (`src/csharp/NativeDependencies.targets`):
  DLLs at `build/<os>/bin/<name>.dll` (Windows: no `lib` prefix, `.dll` ext),
  each exporting its `ke_*_create` symbol. Csprojs list `<NativeDep Include="ke_foo"/>`
  and the targets file copies `build/win/bin/ke_foo.dll` next to the managed output
  via `PreserveNewest`. **The path is a single property (`NativeFinalDir`)** — if
  `zig build` emits DLLs elsewhere, repointing C# is a one-line change. Only the
  **DLL base name + exported `ke_*_create` symbol** are truly load-bearing.
- **Tests:** GoogleTest, discovered by `ctest` via `gtest_discover_tests`
  (`tests/c/kernel`, `tests/cpp`, `tests/integration/cpp`).
- **Extras CMake gives for free:** `compile_commands.json` (clangd), Clang
  source-based coverage across all `src/`+`tests/` targets (`KE_COVERAGE` →
  `scripts/coverage.py`), `cmake --install … --prefix build/native`.

Anything the Zig build does **must** reproduce: same DLL names, same output dir,
same exported symbols, or Layers 3–4 break silently.

---

## 2. The three honest options for "build.zig orchestrates vcpkg"

Zig's build system has **no native vcpkg concept**.

| Option | What it means | Cost | Verdict |
|---|---|---|---|
| **A. vcpkg stays as dep provider; build.zig consumes `vcpkg_installed/`** | `vcpkg install` runs against the manifest; a small `build.zig` module adds the triplet's include/lib paths and links prebuilt `.lib`s. | ~1 day | **Recommended start.** Keeps reproducibility; decouples the build-system swap from any dependency-management change. |
| **B. Drop vcpkg; build every dep from source via Zig** | box2d/flecs/stb/miniaudio/glm/tomlplusplus are trivial in Zig. **bgfx** (genie + own shaderc) and **assimp** (large C++) are *months*. | Months | Out of scope. A separate project, not "switch impl language." |
| **C. Hybrid: vcpkg for heavy C++ libs, `build.zig.zon` for the easy ones** | Migrate easy deps to Zig's package manager as the plugins that use them move to Zig. | Incremental | **Natural end-state**, not the starting point. |

**[DECIDED — PO, 2026-06-17] Option A.** vcpkg is never replaced. `build.zig` does
exactly what Clang+CMake do today: locate the libs vcpkg already installed under
`vcpkg_installed/<triplet>/` and add their include/lib paths. The "trocar o build
system" milestone is explicitly *not* "kill vcpkg" — it is "build.zig drives the
build; vcpkg remains the dependency oracle; build.zig reads its output." Option C
(drifting easy deps to `build.zig.zon`) remains available later but is not required.

---

## 3. Ranked technical risks

1. **Windows ABI choice — the gate (highest).** Today `x64-windows-static-md`
   builds vcpkg ports with **MSVC** (the triplet governs the port toolchain; the
   preset's `clang` setting only affects our own top-level configure). The PO
   dislikes MSVC and wants deps built Clang/Ninja, Linux-style. That means a
   **custom vcpkg triplet**, and an ABI decision:

   - **Preferred — Clang + GNU/mingw ABI (`x86_64-windows-gnu`).** Maximally
     Linux-style, no MSVC, no Windows SDK. **It is also Zig's *default* target**,
     so linking is trivial. **Risk:** heavy C++ ports (**bgfx, assimp**) have
     weaker mingw coverage in vcpkg and may not build cleanly. This is where the
     road can become a rabbit hole.
   - **Fallback — Clang + MSVC ABI (`x86_64-windows-msvc`).** Clang compiler (no
     `cl.exe`), still links against MS CRT + Windows SDK. Less pure, but ports
     build reliably. Zig matches with `-target x86_64-windows-msvc`.
   - **Last resort — MSVC-built ports + Zig msvc target.**

   **Spike decides — and must validate with bgfx + assimp, not just glfw**, since
   those are exactly the ports that break under mingw. Prefer the GNU road; fall
   back gracefully without over-promising what vcpkg may not deliver.

   **MSVC, if chosen, is transitional — not permanent.** The Render V2 migration
   (`docs/RenderArchitectureV2.md`) replaces **bgfx** with **webgpu-native**, which
   ships **pre-built**. That removes one of the two heavy C++ ports from the mingw
   equation — leaving only **assimp** as a holdout. So even if the spike forces
   MSVC ABI today (because of bgfx), the GNU/Linux-style road reopens once Render V2
   lands. **New input this creates:** webgpu-native is distributed in a *specific
   ABI* (wgpu-native ships MSVC + GNU; Dawn prebuilts on Windows are usually MSVC).
   Whichever webgpu-native Render V2 picks, **its prebuilt ABI becomes a linking
   constraint** — confirm it supports a GNU build before assuming the GNU road
   reopens. Track this jointly with the Render V2 plan.
2. **Output-contract parity** — only DLL base name + exported `ke_*_create` are
   load-bearing; the output dir is a one-line `NativeFinalDir` repoint in
   `NativeDependencies.targets`. **Low**, once the symbol export is confirmed.
3. **vcpkg consumption layer** in `build.zig` (Option A). Medium.
4. **Lost-for-free CMake features** — coverage, `compile_commands.json`, ctest +
   gtest discovery, install step. All reproducible (Zig *is* Clang underneath),
   but each is work to re-wire. Medium.
5. **Zig pre-1.0 toolchain churn.** `build.zig` API breaks between 0.12/0.13/0.14.
   Pin an exact version; treat upgrades as deliberate events. Ongoing tax.
6. **Debugging/tooling on Windows** — PDB generation, IDE step-through for Zig.
   Verify in the spike.

---

## 4. Phased plan (build-system first, language second)

**Golden rule:** prove the build system against the *current* code before writing
one line of production Zig. Never swap build + language simultaneously.

### Phase 0 — Spike (go/no-go gate)
- Zig builds a trivial C-ABI DLL exporting `ke_foo_create`.
- **Try a custom Clang + GNU/mingw vcpkg triplet first** (PO preference, §3).
  Build glfw3 **and the heavy ports bgfx + assimp** under it — those decide
  whether the GNU road is viable. Link the resulting libs into a Zig exe
  (Zig's default `windows-gnu` target).
- **If bgfx/assimp don't build on mingw → fall back to Clang + MSVC ABI**, Zig
  targeting `x86_64-windows-msvc`. Still Clang/Ninja, no `cl.exe`.
- C# P/Invokes into the Zig-built DLL successfully.
- Confirm: debug info (PDB vs DWARF depending on ABI), `compile_commands`
  emission, debug stepping.
- **Output of this phase = the chosen ABI + triplet, locked for the rest.**

### Phase 1 — build.zig builds the *existing* tree, zero source changes
- `zig cc` compiles all C and C++ unchanged.
- `build.zig` reads `vcpkg_installed/<triplet>` (Option A).
- Reproduces every target: identical DLL names, output dir (`build/<os>/bin`),
  exported symbols, install copy.
- **Success metric:** all C/C++ tests pass and all C# examples run, against
  artifacts produced *solely* by `zig build`. CMake stays as fallback.
- **No production Zig yet** — this de-risks the build swap from the rewrite.

### Phase 2 — make `zig build` canonical
- Re-wire coverage flags, `compile_commands.json`, a ctest-equivalent test step.
- Reproduce `cmake --install … --prefix build/native` (if still needed; see §1
  note — C# currently reads `build/win/bin` directly via the targets file).
- Delete CMake only once parity is proven and held for a few green cycles.

### Phase 3 — migrate the first plugin to Zig (the template)
- Pick the smallest, lowest-dependency, no-C++-lib target:
  candidate **`ke_logger_simple`** or **`ke_allocator_malloc`** (pure C, no vcpkg
  C++ dep).
- Rewrite impl in Zig; keep the `_create.h` C contract and the exported symbol
  **identical**. `@cImport` the kernel headers for the vtable types.
- Prove the swapped DLL is drop-in: C# bindings and tests unchanged and green.
- This becomes the reference pattern for every later migration.

### Phase 4+ — migrate plugin by plugin, dependency order, lowest risk first
See §5 for ordering. C++-library-bound plugins migrate last or keep a shim.

---

## 5. Migration order (almost everything has a C path)

1. **Pure-C kernel domains first** — logger, allocator, runtime, ecs-glue,
   resource_cache, input. No C++ dependency → pure win, low risk.
   **`src/c/framework/` is already mandated pure-C (project rule 6)** → it is the
   poster child for Zig and an early, high-value target.
2. **Plugins wrapping a library that has a C API** — bgfx (`bgfx/c99/bgfx.h`),
   box2d (C), miniaudio (C), flecs (C), enkiTS (C API), stb (C). Zig `@cImport`s
   the C API directly and the **C++ wrapper is deleted entirely**.
3. **C++-only-API holdouts** — assimp (C++ API), tomlplusplus. Mitigations: toml
   is **already tomlc99** (vendored, C) in the framework; glfw is already a C API.
   assimp is the genuine holdout → keep a thin C++ shim compiled by `zig cc`, or
   swap the loader library.

So the only real C++-API dependency that resists a clean Zig rewrite is **assimp**.

---

## 6. Error model under Zig

The engine's error scheme (`src/c/common/include/kernel_engine/common/error.h`):
`ke_result` = {KE_OK, KE_ERROR}; `ke_error_type` = singleton with a `parent` chain
(pointer-identity match via `ke_error_is`); `ke_error` = `{type, message, file, line,
cause}` in a thread-local ring buffer; populated by `KE_ERROR_SET`/`KE_ERROR_WRAP`
(inject `__FILE__`/`__LINE__`) into an optional `out_error**`.

**Key fact: Zig's *native* error model is poorer than `ke_error`, not richer.** Zig
errors are payload-free integer tags (`error{NotFound, OutOfMemory}`) — you cannot
attach message / file / line / cause / type-hierarchy to them. Zig's "error return
trace" is a debug diagnostic, **not** a propagatable cause chain. So `ke_error`'s rich
context is built *on top* of Zig, exactly as it is built on top of C today — parity,
not a free win, and not a loss.

**Where Zig is strictly better than the C macros:**
- `@src()` — comptime builtin giving `.file/.line/.fn_name/.column` at the call site,
  a first-class replacement for the `__FILE__`/`__LINE__` preprocessor trick (and
  yields fn-name + column for free).
- `errdefer` — error-path cleanup without C's `goto fail` ladder. This is the single
  biggest ergonomic win; C error handling hurts most exactly here.
- `try` — propagation without `if (r != KE_OK) return r;` boilerplate.

**The boundary does not change.** Exported slots still return `ke_result` and take
`out_error**`; the whole `ke_error` machinery is consumed via
`@cImport("kernel_engine/common/error.h")`. Domain error-type singletons become
`export const x: c.ke_error_type = .{ .name = ..., .parent = &c.KE_ERROR_NOT_INITIALIZED }`.

**Recommended pattern — native errors inside, translate at the seam:**

```zig
const c = @cImport(@cInclude("kernel_engine/common/error.h"));

fn errType(e: anyerror) *const c.ke_error_type {
    return switch (e) {
        error.OutOfMemory => &c.KE_ERROR_OUT_OF_MEMORY,
        error.FileNotFound => &c.KE_ERROR_NOT_FOUND,
        else => &c.KE_ERROR_GENERAL,
    };
}

// Replacement for KE_ERROR_SET — fed by @src() instead of __FILE__/__LINE__.
inline fn setErr(out: ?*?*c.ke_error, t: *const c.ke_error_type,
                 msg: [*:0]const u8, src: std.builtin.SourceLocation) c.ke_result {
    return c.ke_error_set(out, t, msg, src.file, src.line, null);
}

export fn ke_window_glfw_create(out_error: ?*?*c.ke_error) callconv(.C) ?*c.ke_window {
    const self = glfwInit() catch |e| {
        _ = setErr(out_error, errType(e), "glfw init failed", @src());
        return null;
    };
    return self;
}
```

**Two review-level caveats:**
1. `KE_ERROR_SET`/`KE_ERROR_WRAP` are function-like macros — `@cImport` does not
   reliably translate those. Zig calls the exported `ke_error_set()` directly and
   injects `@src()`. The macros become an `inline fn` in a shared Zig helper module.
2. `try` alone is **thin propagation** — it bubbles the bare tag and loses the `cause`
   chain. To preserve rich chaining you must `ke_error_set(..., cause)` (the
   `KE_ERROR_WRAP` equivalent) at each layer you care about — identical to choosing
   where to `KE_ERROR_WRAP` in C today. `try` = control flow; `ke_error` chain =
   context. Orthogonal; don't expect `try` to build the chain for you.

**Verdict:** the error scheme survives intact and gets *more* ergonomic (`errdefer`,
`@src()`). The only thing Zig doesn't hand us is the rich layer — which we already
hand-build today.

---

## 7. What we must not lose (parity checklist)

- [ ] DLL names, output dir, exported `ke_*_create` symbols (C# hard contract).
- [ ] Per-domain shared/static toggle (today `BUILD_SHARED_LIBS` + `KE_*_EXPORT`).
- [ ] `compile_commands.json` for clangd/IDE.
- [ ] ~~Clang source-based coverage across all targets~~ — **not achievable as originally scoped; downgraded to known debt.** Verified (2026-07-22): Zig's own linker rejects Clang's profiling-runtime relocations when building a Zig-orchestrated shared library (`fatal linker error: unhandled relocation type R_X86_64_PC64 ... __llvm_prf_data`), so only binaries whose *final link* is done by the system `clang`/`clang++` — today, just the two GTest suites (`test_ke_kernel`, `test_integration_cpp`) — can carry `-fprofile-instr-generate`. `scripts/coverage.cs` now instruments only those two suites' own translation units (see its file header). Engine logic itself is almost entirely Zig now (`src/c/kernel/` and `src/cpp/` were fully migrated), so this isn't a narrow gap — there is currently **no source-based coverage story for the Zig-implemented engine at all**. Closing this needs either (a) a way to make Zig's linker accept/emit the profiling sections for its own shared-library output, or (b) an alternative coverage mechanism for Zig code (e.g. `kcov` wrapping `zig build test` binaries) — neither attempted yet.
- [ ] ctest-equivalent running the GoogleTest executables (tests stay C++ under
      `zig cc` until/unless ported to `zig build test`).
- [ ] Install/copy step feeding the C# native-dep copy.
- [ ] Shader pipeline (`scripts/compile_shaders.py`) and binding regen
      (`scripts/generate_bindings.cs`) are orthogonal — unaffected, but verify.
- [ ] Linux parity (`x64-linux`), not just Windows.

---

## 8. Decisions

**Settled (PO, 2026-06-17):**
- **End-state scope** — pragmatic. Zig where excellent, keep C/C++ dep otherwise.
  Not "zero C++ at all." §0.
- **vcpkg strategy** — Option A. vcpkg stays; build.zig consumes `vcpkg_installed/`. §2.
- **CMake** — to be removed (it is the explicit driver of the project), once
  build.zig parity is proven (trigger below still open).

**Settled (PO, 2026-06-20):**
- **Pinned Zig version** — 0.16.x (latest stable at time of work; verify on
  ziglang.org — if 0.16 is not yet released, pin the latest available stable and
  upgrade to 0.16 when it lands).
- **Test framework fate** — migrate to Zig's built-in `test` blocks progressively:
  as each module moves to Zig, its GoogleTest suite moves to `zig build test`.
  C++ modules keep GoogleTest under `zig cc` until their Zig port.
- **CMake retirement trigger** — 1 green cycle (build.zig produces identical DLLs,
  all C++ tests pass, all C# examples run) + PO manual validation of runtime
  examples. CMake deleted immediately after that session.

---

## 9. First concrete step when work begins

Phase 0 spike only — a throwaway branch:
1. `build.zig` that produces `ke_spike.dll` exporting one `ke_spike_create`.
2. Custom Clang+GNU triplet first: build glfw3 **+ bgfx + assimp**, link into a Zig
   exe (`windows-gnu`). If the heavy ports don't build → Clang+MSVC ABI fallback.
3. A 20-line C# `[DllImport]` smoke test calling `ke_spike_create`.

Green spike = go. Then Phase 1. Nothing in `src/` changes until Phase 3.

---

## 10. Work log — where we paused (2026-06-20)

**Branch:** `spike/zig-build` (stashed as "Phase 1 build.zig WIP" — the Phase 0 spike was already completed and work had begun on Phase 1).

**What happened:** Before the spike began, a C# namespace cleanup was needed on `main`.
The `feat/kernel-v2` merge had dissolved `KernelEngine.Kernel` into domain packages
(`KernelEngine.Logger`, `KernelEngine.Ecs`, etc.) but left ~80 source files still
declaring `namespace KernelEngine.Kernel;` and ~100 consumer files still
`using KernelEngine.Kernel;`. Also, 22 example/test csproj files had a broken
`<ProjectReference>` to the deleted `kernel/KernelEngine.Kernel/` path.

All of that was cleaned up on `main` (session 2026-06-20):
- All source files renamed to domain namespaces.
- All consumer `using KernelEngine.Kernel;` directives replaced with domain usings.
- Broken project references removed from all 22 csproj files.
- Test namespace moved to `EngineTests` to avoid C# namespace-hierarchy ambiguity.
- `dotnet build KernelEngine.slnx` → **0 errors, 0 warnings**.

**Next step when resuming Zig work:**
1. `git stash pop` on `spike/zig-build`.
2. Begin §9 Phase 0 spike: write a minimal `build.zig` that compiles one C file and
   produces `ke_spike.dll` exporting `ke_spike_create`.
3. Validate triplet choice (Clang+GNU vs Clang+MSVC ABI) against glfw3 + bgfx link.
