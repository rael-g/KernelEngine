# Done — KernelEngine Achievements Log

Archival list of completed work, extracted from `docs/Kanban.md` so the active board doesn't grow unbounded. New entries append to the bottom; nothing is ever deleted here. The Kanban itself only holds active and roadmap items.

---

## Pre-extraction (legacy entries)

- [x] **[Y.4] Symbolic Result Names**: `KernelException` maps all `ke_result` codes.
- [x] **[W.4] Microkernel Hardening**: Moved TLS/Utilities from C++ plugin to C kernel.
- [x] **[P Wave 1] PAL Foundation**: `IDevPlatform` with Win32/Posix backends.
- [x] **[F] Structured Shutdown**: `join_timeout` + `CancellationTokenSource`.
- [x] **[H] MessagePipe Removal**: Dead code eliminated.
- [x] **[E] API Migration**: Examples 01–05 using `IResourceFactory`/`ISceneWriter`.
- [x] **[Y.1] bgfx Fatal Callback**: Captures file/line on abort.
- [x] **[Y.7-Y.9] Observability**: Log flush, SEH handler, Lifecycle logs.
- [x] **[B] Dead Code removal**: `GlfwWindow.cpp` deleted.
- [x] **[A] Handle Safety**: `UINT32_MAX` sentinel and typed handles.

## Sweep 2026-06-05 — legacy Kanban "BLOCK 5 cleanup" archive

Cleanup cards completed during the multithread-architecture branch consolidation. Full bodies removed from `Kanban.md` to keep it focused on live work.

- [x] **[W.4] Layer Boundary Cleanup (Phase 2)** — commit `9a87a37`. Public API leaks closed in `src/cpp/render/`.
- [x] **[W.6] Move Internal-Only render/core Headers from `include/` to `src/`** — commit `2131aa2`.
- [x] **[W.7] Move `get_last_fatal_error` from bgfx Plugin to `ke_render` Vtable** — commits `2131aa2`, `a97d9a8`, `9a87a37`.
- [x] **[W.8] Rename Namespace `kernel_engine::render::bgfx` → `kernel_engine::render::core`** — commit `2131aa2`.
- [x] **[W.9] Promote `render/core` to Standalone Agnostic Plugin (eliminate "system factory" pattern)** — `bgfx_system_factory.h` deleted; `render/core` exports one `_create` entry point; backend swap = implement `ke_render` vtable + reuse `render/core` unchanged.
- [x] **[W.10] Audit `bgfx_shader_compiler` Plugin (class in public header + wrong extensions)** — commits `e953bcc`, `b41bf88`.
- [x] **[W.11] Fix File Extensions (`.hh` → `.hpp`, `.cc` → `.cpp`)** — commit `e953bcc`.
- [x] **[W.12] Rename PascalCase Filenames to snake_case (16 files)** — commit `a3f9e0d`.
- [x] **[W.13] Remove `using namespace` Violations** — no remaining occurrences in `src/cpp` or `src/c` headers.
- [x] **[W.14] Misc Naming/Structure Cleanups** — `enki_task_scheduler` header rename, plugin threading consolidation, `_export.h` standardized location (commits `2b6f9f4`, `a462d75`, `36551ce`).
- [x] **[W.15] Eliminate `src/csharp/Native/` Folder — Single Project per Plugin** — commit `2131aa2`.
- [x] **[W.16] Move `ke_console_sink_create` Out of the Kernel** — commit `ecbad90` (Option B).
