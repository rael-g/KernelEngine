# Render Architecture V2 — utopian renderer layered on a WebGPU-style core

**Status**: Accepted at design level (2026-06). Re-homed onto a fresh branch (`feat/render-v2-zig`) cut from current `main` — the previous `feat/render-v2` fell 128 commits behind, predating the kernel include reorg, the `bool` + `ke_error**` ABI idiom, and the handle-ownership refactor. Only the design knowledge, the Slang shaders, and the L3 C ABI headers were carried forward; all C++ implementation was discarded (see §16).
**Implementation language**: **Zig** (see §15). The C ABI surface stays C — `extern "C"` headers under `src/c/render/include/` — exactly as every other engine contract. Zig is the impl language behind that ABI, not a new boundary.
**Audience**: Engine maintainer + future render plugin authors + game devs writing custom shaders/passes.
**Companion docs**: [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md) — `ke_runtime` (scheduler), `ke_ecs` (storage), `ke_world` (framework aggregator), `components.h` (the component vocabulary the renderer reads), §16 (per-component snapshot pipelining), §17 (the V1 merge arc that deleted the LEGACY `*_render_system.cpp` extract path). [`ZigMigrationPlan.md`](ZigMigrationPlan.md) — the incremental Zig adoption strategy this renderer is the first greenfield instance of.

**Integration model — the short version**: the renderer is a runtime **Module** that pins its passes to a worker named `ke.render` and reads `Camera`/`Light`/`Mesh` components straight from `ke_ecs` via `ke_system_ctx`. There is no extract phase that writes a frame packet; once R6 wires up the per-component snapshot back-buffer (§16 of the runtime doc), render passes read the snapshot side while sim writes the live side. Pre-R6 transitional state runs sim and render serially on the same world — no pipelining, no separate handoff buffer. Frame packet is **not part of the V2 contract**.

---

## 1. Purpose

The current renderer (`KernelEngine.Render.Bgfx`) is **functional and shipping** but has structural problems that will only get worse as we add modern techniques:

1. **`GpuDevice` API is OpenGL/DX11-era stateful** — `SetState` / `SetUniform` / `Submit` per draw. The control bgfx gives us over Vulkan memory + barriers is *literally not used* because the abstraction above it pretends GL exists.
2. **Hundreds of direct `gpu_device->` calls scattered across the renderer** — any change to the device API breaks 500 sites at once. Swapping the device is a 3-month project.
3. **No PSO management** — bgfx hides pipeline state objects entirely. When we move to a backend that exposes them (WebGPU-style), we'll either copy Godot's mistake (lazy compile + runtime stalls forever) or design the **three-mechanism solution** (ubershader fallback + build-time manifest + per-machine disk cache — see §6). The mechanisms compose; copying just one leaves the player with stutters. We design all three *now*, before the problem exists.
4. **Shader pipeline is bgfx `.sc`** — a preprocessor over GLSL. No modules, no generics, no interfaces. Slang exists; Slang is the future; the migration has to happen at some point.
5. **No mid-level abstractions** — the renderer is "high-level features call the low-level device directly". There's no `RenderPass` / `ComputePass` / `MaterialBinding` layer to absorb backend changes.

This doc defines the **target renderer architecture** — what we build *alongside* the current one, as a new Zig lib (`KernelEngine.Render.Modern`), so the old one keeps shipping while the new one matures. When V2 reaches feature parity, swap default. The bgfx-based renderer survives as a fallback DI choice (and a real-world test that we didn't accidentally bake new-stack assumptions into game code).

**Doctrine sentence**: *the renderer is a stack of layered abstractions; each layer encapsulates the one below; game code (and most engine code) never touches the GPU device directly.*

---

## 2. Layered architecture (the big picture)

```
┌──────────────────────────────────────────────────────────────────────┐
│  L7 — High-level capabilities (LOD selector, RT denoiser, GI,        │
│       upscaler, hair, volumetric, etc.) — each ships as a render      │
│       pass (or pass set) registered as a runtime system              │
├──────────────────────────────────────────────────────────────────────┤
│  Passes — NOT a layer object. Each render pass is a plain runtime     │
│       system (register_system); the runtime's wave-builder orders     │
│       passes by access-list. No graph object, no Kahn topo-sort.      │
├──────────────────────────────────────────────────────────────────────┤
│  L5 — Render core (C ABI service): pass context + resource registry   │
│       + transient pool + barriers + PipelineCache / MaterialBinding   │
│       / ResourceUploader / CommandRecorder. Owns no draw.             │
├──────────────────────────────────────────────────────────────────────┤
│  L4 — Encoder & queue surface (CommandEncoder, RenderPass,           │
│       ComputePass, CommandBuffer — typed objects, gpu_commands.h)     │
├──────────────────────────────────────────────────────────────────────┤
│  L3 — `ke_gpu_device` C ABI (WebGPU-style — Device, Buffer,          │
│       Texture, Sampler, ShaderModule, Pipeline, BindGroup)            │
│       + `query_extension` (§4.5)                                      │
│                                                                       │
│       Extension vtables (queried from device, kernel-agnostic):       │
│       ke_gpu_raytracing / ke_gpu_mesh_shader / ke_gpu_bindless /      │
│       ke_gpu_sparse_resources / ke_gpu_work_graph / ke_gpu_profiler   │
├──────────────────────────────────────────────────────────────────────┤
│  L2 — Backend impl (webgpu-native today; Vulkan/D3D12 direct later)  │
├──────────────────────────────────────────────────────────────────────┤
│  L1 — OS / driver                                                     │
└──────────────────────────────────────────────────────────────────────┘
```

**Rules of the road**:
- Each layer talks only to the layer immediately below. A high-level pass *never* calls L3 core directly — extensions are the one sanctioned reach-through (§4.5, §7.2).
- **L3 is the C ABI** — lives at `src/c/render/include/kernel_engine/render/gpu_device.h`, in the render domain. C ABI only; no privileged caller language (see §4.0).
- L3 extensions (ray tracing, mesh shaders, bindless, etc.) are queried from the device via `query_extension` — the engine knows nothing about them individually. See §4.5.
- **L4 and L5 are C ABI** (Option A, §13.3). L4 (`gpu_commands.h`) is the typed recording surface — `ke_gpu_command_encoder` / `ke_gpu_render_pass` / `ke_gpu_compute_pass` are C structs the device fills via `create_command_encoder`. L5 (the render core: a `ke_render_service` service + the `ke_render_pass_ctx` handed to each pass) is a C ABI whose implementation is Zig. Any module — C, Zig, or C# — authors render passes against L4+L5.
- **There is no render-graph object and no `ke_render` (L7 vtable) in V2.** A render pass is a plain runtime system; the runtime orders passes (§7). `render.h` / `render_graph.h` / `frame_packet.h` are V1 (bgfx) legacy — untouched by V2 and not part of this design.
- High-level capabilities (L7) ship as render passes (or pass sets) registered as runtime systems — in plugins (`KernelEngine.Render.<Feature>`) or in the game itself.
- The Zig source tree is `src/zig/render/` (backend + core); the C ABI headers live in `src/c/render/include/` (§13.2).

---

## 3. Core concepts (vocabulary)

### 3.1 Device

The opaque handle to a configured GPU + driver + Vulkan/D3D12/Metal context. Created once at engine init; lives for the program lifetime. No state except resource ownership. **Closely models `GPUDevice` from the WebGPU spec.**

A Device is the only entity that creates: Buffers, Textures, Samplers, ShaderModules, Pipelines, BindGroupLayouts, BindGroups, CommandEncoders.

### 3.2 Queue

Where command buffers go to execute. One graphics queue; potentially additional async-compute or transfer queues on capable backends.

### 3.3 CommandEncoder

A short-lived recording context. You ask the Device for an encoder, begin one or more passes (render or compute) on it, finish it into an immutable CommandBuffer, submit to a Queue.

```
Device → CommandEncoder → RenderPass → draws → end → CommandBuffer → Queue
                       └→ ComputePass → dispatches → end ↗
```

### 3.4 RenderPass / ComputePass

Scoped recording sub-contexts. A RenderPass declares its attachments (color targets, depth) and load/store ops at begin; within the pass you set pipeline + bind groups + buffers and issue draws.

### 3.5 Buffer / Texture / Sampler

Standard GPU resources. Created from the Device with explicit usage flags (`VERTEX | UNIFORM`, `SAMPLED | STORAGE`, etc.) so the backend can place them in the right heap.

### 3.6 ShaderModule

An opaque container around compiled shader bytecode (SPIR-V on Vulkan, DXIL on D3D12, MSL on Metal). Produced by the Slang frontend; consumed by Pipeline creation.

### 3.7 Pipeline (PSO)

The Pipeline State Object — the precompiled combination of (vertex layout + shader stages + rasterizer state + blend state + depth state + bind group layout). **Async-compiled, cached, placeholder-on-miss** (see §6).

### 3.8 BindGroupLayout / BindGroup

The "descriptor set" equivalent. A BindGroupLayout declares "this group has 1 uniform buffer at binding 0, 1 sampler + texture at binding 1". A BindGroup is an instance filling that layout with real resources.

### 3.9 Mid-level: RenderPassBuilder, ComputePassHelper, MaterialBinding, ResourceUploader, CommandRecorder

These live above the device but below render-graph and high-level features. **The most important architectural decision in this doc.** Detailed in §5.

---

## 4. C ABI — `ke_gpu_device` (L3)

Lives at `src/c/render/include/kernel_engine/render/gpu_device.h`, with `gpu_enums.h` (formats, usages, states) and `gpu_commands.h` (encoder + pass surfaces) beside it. Replaces the bgfx-era C++ `GpuDevice` class.

### 4.0 Conventions — these headers obey the current engine ABI idiom

The previous branch's headers predated three convention shifts now standard on `main`. The re-homed headers follow the canonical shape, taking `src/c/render/include/kernel_engine/render/render.h` (`ke_render`) as the reference precedent:

1. **No privileged caller language.** There is exactly one C ABI; C is not special. The previous branch shipped ~200 lines of `static inline ke_gpu_device_*` / `ke_gpu_render_pass_*` forwarders "to make C callers ergonomic" — **deleted**. A caller invokes a vtable slot directly: `dev->create_buffer(dev, &p, &err)`. The only inline helpers that survive are trivial *value* predicates / typed casts (`ke_gpu_is_valid`, the §4.5 typed-extension query) — the same category as `ke_mesh_is_valid` in `handles.h`. Those are not method forwarders.
2. **`bool` + `ke_error **out_error`, never `ke_result` in slots.** Fallible operations return `bool` and take `ke_error **out_error` as the last parameter (`KE_ERROR_SET` populates it). Handle-returning fallible operations return the handle directly and take `ke_error **out_error`. The previous branch's `ke_result (*wait_fence)(...)` is reshaped to `bool (*wait_fence)(..., ke_error **out_error)`.
3. **Ownership via a separate `_handle` owner-wrapper, not a `(*destroy)` slot in the vtable.** The device vtable has no `destroy`. The factory returns `ke_gpu_device_handle { ke_gpu_device *ref; void (*destroy)(ke_gpu_device *self); }`; dependencies receive the borrow `ke_gpu_device *` (cannot destroy). Same pattern as `ke_render_handle`. *(Transient per-frame objects — encoder, render pass, compute pass — keep an `end`/`finish`/`destroy` slot in their own surface; they are not long-lived owned roots, and the owner-wrapper pattern is reserved for those.)*
4. **The vtable IS the named struct.** Function pointers live directly inside `ke_gpu_device` (a `void *handle` plus the slots), exactly like `ke_render` — not a separate `ke_gpu_device_vtable` typedef plus an instance struct holding a `vtable*`. This collapses the previous branch's two-tier split.
5. **Single typed surface for command recording.** The previous branch exposed recording *twice*: flat `rp_*` / `cp_*` / `encoder_*` primitives over `void*` on the device, **and** typed `ke_gpu_render_pass` / `ke_gpu_compute_pass` wrapper structs that merely forwarded to them. The duplication is removed: the encoder/pass objects (`gpu_commands.h`) carry their recording slots directly; the device creates them and is done. One way to record.

### 4.1 Opaque resource handles

```c
typedef uint64_t ke_gpu_buffer;
typedef uint64_t ke_gpu_texture;
typedef uint64_t ke_gpu_texture_view;
typedef uint64_t ke_gpu_sampler;
typedef uint64_t ke_gpu_shader_module;
typedef uint64_t ke_gpu_pipeline;
typedef uint64_t ke_gpu_bind_group_layout;
typedef uint64_t ke_gpu_bind_group;
typedef uint64_t ke_gpu_queue;
typedef uint64_t ke_gpu_fence;

#define KE_GPU_INVALID_HANDLE UINT64_MAX
```

Resources are 64-bit handles, not raw pointers — decouples the app from backend memory layout, and leaves room for generation+index packing. *(Open, §13.5: whether to struct-wrap these as `{ uint64_t id; }` for the same type-safety the render handles get in `handles.h`. The bare-`uint64_t` form matches the WebGPU C API style and the previous branch; struct-wrapping costs nothing at runtime and prevents cross-handle mix-ups.)*

### 4.2 Device vtable (essential surface — full surface enumerated when impl starts)

The shape, in the canonical idiom (abridged):

```c
typedef struct ke_gpu_device {
    void *handle;

    // Queue
    ke_gpu_queue (*get_default_queue)(struct ke_gpu_device *self);
    bool (*queue_submit)(struct ke_gpu_device *self, ke_gpu_queue q,
                         ke_gpu_command_buffer *const *cmds, uint32_t cmd_count,
                         ke_error **out_error);
    bool (*queue_present)(struct ke_gpu_device *self, ke_gpu_queue q, ke_error **out_error);

    // Resource creation (returns KE_GPU_INVALID_HANDLE + sets out_error on failure)
    ke_gpu_buffer        (*create_buffer)(struct ke_gpu_device *self, const ke_gpu_buffer_params *p, ke_error **out_error);
    ke_gpu_texture       (*create_texture)(struct ke_gpu_device *self, const ke_gpu_texture_params *p, ke_error **out_error);
    ke_gpu_shader_module (*create_shader_module)(struct ke_gpu_device *self, const ke_gpu_shader_module_params *p, ke_error **out_error);
    ke_gpu_pipeline      (*create_render_pipeline)(struct ke_gpu_device *self, const ke_gpu_render_pipeline_params *p, ke_error **out_error);
    // ... sampler, texture_view, compute_pipeline, bind_group_layout, bind_group

    // Resource destruction (deferred to next safe frame internally — infallible, void)
    void (*destroy_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h);
    void (*destroy_texture)(struct ke_gpu_device *self, ke_gpu_texture h);
    // ... per resource type

    // Encoder factory (returns the typed L4 object — see gpu_commands.h)
    ke_gpu_command_encoder * (*create_command_encoder)(struct ke_gpu_device *self, ke_error **out_error);

    // Mapped writes (streaming uploads — see ResourceUploader §5.3)
    void * (*map_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h, size_t offset, size_t size, ke_error **out_error);
    void   (*unmap_buffer)(struct ke_gpu_device *self, ke_gpu_buffer h);

    // Capabilities — pure getter, cannot fail, no out_error
    void (*get_capabilities)(struct ke_gpu_device *self, ke_gpu_capabilities *out);

    // Extension query — the ONLY thing the engine learns about extensions (§4.5)
    void *(*query_extension)(struct ke_gpu_device *self, const char *name);
} ke_gpu_device;

typedef struct ke_gpu_device_handle {
    ke_gpu_device *ref;
    void (*destroy)(ke_gpu_device *self);
} ke_gpu_device_handle;
```

**Recording slots are infallible `void`** (set_pipeline, draw, dispatch, …). This mirrors WebGPU's own model: recording cannot fail synchronously; validation surfaces at `finish`/`submit`. Forcing `bool + out_error` on every per-draw call would be hot-path noise for no benefit. The fallible seams are creation, mapping, fence wait, and submit/present — those carry `out_error`.

### 4.3 CommandEncoder + Pass surface (L4, `gpu_commands.h`)

Each is a typed object: `void *handle` (the backend's encoder/pass), a `device` backref, and its recording slots inline (same single-struct idiom as the device). No separate `_vtable` typedef, no forwarders.

```c
typedef struct ke_gpu_render_pass {
    void                 *handle;
    struct ke_gpu_device *device;

    void (*set_pipeline)(struct ke_gpu_render_pass *self, ke_gpu_pipeline pipe);
    void (*set_bind_group)(struct ke_gpu_render_pass *self, uint32_t group_index,
                           ke_gpu_bind_group bg, const uint32_t *dynamic_offsets, uint32_t dyn_count);
    void (*set_vertex_buffer)(struct ke_gpu_render_pass *self, uint32_t slot, ke_gpu_buffer b, size_t offset);
    void (*set_index_buffer)(struct ke_gpu_render_pass *self, ke_gpu_buffer b, ke_gpu_index_format fmt, size_t offset);
    void (*set_viewport)(struct ke_gpu_render_pass *self, float x, float y, float w, float h, float min_d, float max_d);
    void (*set_scissor)(struct ke_gpu_render_pass *self, int32_t x, int32_t y, uint32_t w, uint32_t h);
    void (*draw)(struct ke_gpu_render_pass *self, uint32_t vert_count, uint32_t inst_count, uint32_t first_vert, uint32_t first_inst);
    void (*draw_indexed)(struct ke_gpu_render_pass *self, uint32_t idx_count, uint32_t inst_count, uint32_t first_idx, int32_t base_vert, uint32_t first_inst);
    void (*draw_indirect)(struct ke_gpu_render_pass *self, ke_gpu_buffer indirect, size_t offset);
    void (*end)(struct ke_gpu_render_pass *self);
} ke_gpu_render_pass;
```

`ke_gpu_compute_pass`, `ke_gpu_command_encoder` (with `begin_render_pass` / `begin_compute_pass` / `pipeline_barrier` / `copy_*` / `finish` / `destroy`), and `ke_gpu_command_buffer` follow the identical shape. Mesh-shader draws and ray dispatch are **not** here — they arrive through extensions (§4.5).

### 4.5 Extension model — capabilities beyond WebGPU core

`ke_gpu_device` is intentionally constrained to what every backend can implement (the WebGPU-synthesized common ground). Capabilities outside that set — ray tracing, mesh shaders, bindless, sparse resources, work graphs, video decode, profiling, etc. — are exposed through a **typed extension query**, not through new vtable slots on `ke_gpu_device`.

The WebGPU authors are smarter than us. If a capability isn't in their API, it's because no formulation satisfied all backends cleanly. Adding it to `ke_gpu_device` anyway means: either the WebGPU impl returns an error (surprising the caller) or some backend does nothing (lying). Neither is acceptable. Extensions are the honest answer.

#### 4.5.1 The query mechanism (one new slot on the device)

```c
/// Returns a borrowed vtable pointer for the named extension, or NULL if the backend
/// does not support it. Valid for the device lifetime; not owned by the caller.
/// Callers MUST treat NULL as "extension unavailable" and degrade gracefully.
void *(*query_extension)(struct ke_gpu_device *self, const char *name);
```

That is the **only** thing the engine ever learns about extensions. The kernel does not know `ke_gpu_raytracing`, `ke_gpu_mesh_shader`, or anything else. It only knows that `query_extension` exists.

#### 4.5.2 Extension contract shape

Each extension is a C vtable with its own contract header under the render domain, following the same pattern as every other domain header:

```
src/c/render/include/kernel_engine/render/ext/
    gpu_raytracing.h          ← vtable + types
    gpu_mesh_shader.h
    gpu_bindless.h
    gpu_sparse_resources.h
    gpu_work_graph.h
    gpu_video.h
    gpu_profiler.h
    gpu_shader_reflection.h
```

Each header defines the extension vtable struct, a canonical name constant, and a typed query helper (a trivial cast — the §4.0 exception, not a method forwarder):

```c
#define KE_GPU_EXT_RAYTRACING "ke_gpu_raytracing"

static inline ke_gpu_raytracing *
ke_gpu_query_raytracing(ke_gpu_device *dev) {
    return (ke_gpu_raytracing *)dev->query_extension(dev, KE_GPU_EXT_RAYTRACING);
}
```

Caller:
```c
ke_gpu_raytracing *rt = ke_gpu_query_raytracing(device);
if (!rt) { /* degrade: no RT, use shadow maps */ return; }
rt->build_blas(rt, &params, &err);
```

#### 4.5.3 Backend responsibility

Each backend implements `query_extension` by name:
- **webgpu-native backend** (today): returns `NULL` for everything beyond the WebGPU spec — callers degrade cleanly. (wgpu-native exposes some native extensions via `webgpu.h` + `wgpu.h`; expose those that map cleanly, NULL the rest.)
- **Direct Vulkan backend** (later): returns vtables for every extension the physical device reports (`VK_KHR_acceleration_structure`, `VK_EXT_mesh_shader`, …).
- **D3D12 backend** (later): same, mapped to D3D12 feature tiers.

The backend is the only entity that knows which extensions it supports. The engine doesn't. L4/L5/L6/L7 consume extensions through the vtables, never through backend-specific code paths.

#### 4.5.4 What belongs here vs in `ke_gpu_device`

| Capability | Belongs in | Reason |
|---|---|---|
| Buffers, textures, samplers, pipelines, bind groups | `ke_gpu_device` core | WebGPU implements all of these — truly universal |
| `ke_gpu_capabilities` flags (RT? mesh shaders?) | `ke_gpu_device.get_capabilities` | Querying *whether* a capability exists is universal; using it is not |
| Ray tracing BLAS/TLAS, RT pipeline | `ke_gpu_raytracing` extension | Not in WebGPU; Vulkan/D3D12 only |
| Mesh shader dispatch | `ke_gpu_mesh_shader` extension | Not in WebGPU core; widely available but not universal |
| Bindless descriptor indexing | `ke_gpu_bindless` extension | Not in WebGPU; critical for GPU-driven rendering |
| GPU work graphs | `ke_gpu_work_graph` extension | DX12 Agility SDK only as of 2026 |
| GPU-side profiling / timestamp queries | `ke_gpu_profiler` extension | WebGPU has `timestamp-query` behind a flag — not guaranteed |
| Slang reflection at runtime | `ke_gpu_shader_reflection` extension | Build-time reflection is doctrine (§8); runtime reflection is a tools escape hatch |

**Rule of thumb**: if WebGPU ships it (even experimentally), it goes in the core or `ke_gpu_capabilities`. If WebGPU hasn't shipped it, it goes in an extension.

### 4.6 First backend impl: `ke_gpu_device_webgpu`

The first backend wraps **webgpu-native** through the standard `webgpu.h` C API, brought in via the [`eliemichel/WebGPU-distribution`](https://github.com/eliemichel/WebGPU-distribution) CMake wrapper with `WEBGPU_BACKEND=WGPU` (wgpu-native — the Rust implementation — under the hood; `DAWN` is the swap-in alternative). This is the same lib the previous branch used.

Under the Zig pivot, the backend is a Zig module that `@cImport("webgpu.h")` and fills `ke_gpu_device` slots by translating to `wgpu*` calls — a near-mechanical mapping, since WebGPU's API was *literally the design source* for the L3 ABI. "Plug the wheel" doctrine applied to the device backend itself.

The webgpu distribution ships **pre-built** (a linking constraint tracked jointly with `ZigMigrationPlan.md` §3 — confirm the prebuilt ABI matches the chosen Zig target before assuming a GNU road). It is linked by the render-v2 lib's own `build.zig`, which coexists with the rest of the CMake tree (§15).

Caveat: wgpu-native is a Rust runtime under the hood (~5MB binary dependency). If we ever want zero non-engine runtime in the device, the §2 layered architecture lets us write a **direct Vulkan backend in Zig** as a second `ke_gpu_device` impl — the L4/L5/L6/L7 stack above it never changes. That is a deliberate later project, not the starting point (§13.1).

### 4.7 Math ownership + the NDC convention (locked 2026-06-22)

**The engine implements zero matrix math.** Linear algebra is decentralized — every module/language brings its own library, exactly as it brings its own anything-else:

| Consumer | Math library |
|---|---|
| C# game / framework | `System.Numerics` (BCL — `CreatePerspectiveFieldOfView`, `CreateLookAt`, …) |
| C++ game / plugin | GLM (added by that project) |
| Zig module (render core, passes) | **zmath** (zig-gamedev) — SIMD, `[0,1]`-depth perspective builders |

`ke_mat4 { float[16] }` in `common/math.h` is purely an **ABI carrier** — a POD struct that crosses the boundary, never a math API. `math.h` stays types-only and may shrink (the two legacy inline helpers move out to their consumers over time). Zig std has no linear algebra (only scalar `std.math` + the `@Vector` builtin), which is why a Zig module that computes brings zmath; this is not a gap to fill in-engine.

**The single centralization point is the NDC convention** — the one math-adjacent fact only the backend knows. Ported from the legacy `render.h`, it lives on the L3 device:

```c
typedef struct ke_ndc_convention {
    ke_bool z_zero_to_one; // 1 = clip z in [0,1] (Vulkan/D3D/WebGPU), 0 = [-1,1] (GL)
    ke_bool y_flip;        // 1 = framebuffer origin top-left needs Y flip in projection
    ke_bool left_handed;   // 1 = left-handed clip space, 0 = right-handed
} ke_ndc_convention;

ke_ndc_convention (*get_ndc_convention)(struct ke_gpu_device *self);
```

This is the **same pattern as `shader_language()`** (§4.2): the backend *advertises a convention the consumer must respect*; the engine computes nothing. The consumer queries it and configures its own library's projection builder accordingly.

**Matrices are built in the pass, not the consumer.** The forward pass (Zig + zmath) is one hop from L3, so it queries `get_ndc_convention` once and builds the projection correctly in **one place** — instead of spreading NDC-correctness across every consumer (C#, a C++ game, a Lua script), each of which could get it wrong. The split by owner:

| Matrix | Producer | How it reaches the pass |
|---|---|---|
| **Model (world)** | transform / scene-hierarchy system (upstream) | already in `Transform.world_matrix` as `float[16]` — the pass **reads** it, never computes it |
| **View + Projection** | **the pass** | reads `Camera` + the camera's `Transform` + device NDC → zmath |

So a consumer stays **render-math-free**: it sets `Camera { fov, near, far }` + `Transform { position, rotation }` components and nothing else. The pass owns view-proj; the transform system already owns world matrices.

**Escape hatch (noted, not built):** V1 gave C# full control via `SetViewTransform(view, proj)`. Model B trades that for simplicity, so for exotic projections (oblique frustum, custom ortho) the `Camera` component carries an optional explicit view-proj override that, when set, supersedes the in-pass build. Keeps the common case simple without closing the door on the advanced one.

---

## 5. Mid-level abstractions — the render core (L5, C ABI + Zig impl)

This is where the architecture earns its keep. Every render technique above (RenderPass setup, draw issuance, resource binding) is **expressed in terms of these helpers, not directly against the device**. When we swap backends or evolve the device ABI, only a handful of Zig files change instead of 500 call sites.

These helpers ship as the **render core**: a **C ABI service** (Option A, §13.3) — so any module, C/Zig/C#, can author render passes — whose implementation is Zig consuming the L3 C ABI in-language. The C ABI surface is two things: the `ke_render_service` service (resource registry + transient pool + barriers, §7) and the `ke_render_pass_ctx` handed to each pass's `execute` body (§7.2). The Zig helpers below (`RenderPassBuilder`, `MaterialBinding`, `PipelineCache`, …) are reached *through* that context — a pass calls `ke_render_service_begin_pass` and records against the returned `ke_render_pass_ctx`; it never constructs an encoder or touches the device.

### 5.1 `RenderPassBuilder`

Wraps the device's RenderPass with material/pipeline-aware ergonomics. Caller never touches viewport math, pipeline switching, or bind group resolution.

```
// Pseudocode — actual API designed during the impl spike
var pass = RenderPassBuilder.begin(device, encoder, .{
    .color_targets = .{ swapchain_view },
    .depth_target  = depth_view,
    .clear_color   = .{ 0.1, 0.1, 0.2, 1.0 },
});

for (visible_meshes) |m| {
    pass.bindMaterial(m.material);  // resolves PSO + bind groups; PSO miss → placeholder
    pass.setTransform(m.xform);     // updates per-draw uniform
    pass.drawMesh(m.mesh);          // sets vertex/index buffer + draw call
}

pass.end();  // emits render_pass.end + destroy
```

The pass tracks current pipeline / bind groups internally and elides redundant binds (Vulkan/D3D12 don't deduplicate this automatically).

### 5.2 `ComputePassHelper`

Same idea for compute: `bindShader` / `setStorageBuffer` / `setStorageImage` / `dispatch` / `end`. Barrier insertion is handled where the backend needs it (already covered by render-graph at the higher level — see §7).

### 5.3 `ResourceUploader`

Schedules CPU→GPU uploads off the hot path. Critical for streaming and large asset loads.

- **Staging ring buffer** owned by the uploader (configurable size, e.g. 64MB).
- Caller `enqueueUpload(buffer, data, size)` returns immediately.
- Uploader copies into staging on a worker, records the copy command on the encoder later.
- Multi-frame in flight: the ring rotates per frame; never overwrites in-use staging memory.

Replaces the current "synchronous upload via map/unmap on render thread" pattern that blocks render whenever an asset loads. Threading goes through the shared `ke_task_scheduler` — never a private thread (§9, project rule 5).

### 5.4 `MaterialBinding`

Given a `Material` (shader + parameter values + texture refs), resolves to a cached `ke_gpu_pipeline` (via `PipelineCache`, §6), a cached or freshly-built `ke_gpu_bind_group`, and the per-draw uniforms it needs. One `applyTo(render_pass)` call replaces dozens of low-level bind calls.

### 5.5 `CommandRecorder`

Sorts queued draws by material/depth/whatever, builds the command buffer in one pass, submits. The renderer enqueues draws "logically" (mesh, material, transform); the recorder decides issue order. This is where future GPU-driven rendering plugs in: instead of one CPU-side recorder, the recorder builds a draw-call buffer + dispatches indirect from a compute shader.

### 5.6 `PipelineCache`

Owns PSO lifecycle. Detailed in §6. **Status: Mechanism 1 shipped** (2026-07-11/13,
`refactor/ecs-memory-safety`) — `ke_render_service::get_or_create_pipeline` is the sole PSO authority
every pass (in-tree or a game's own) routes through; see §6 Mechanism 1 for the as-built record.

---

## 6. PSO architecture — three mechanisms working together

The Godot mistake worth understanding precisely: it isn't that they "forgot" to cache PSOs; it's that their architecture allows **runtime shader generation via script**, and PSO state spreads across forward/shadow/gbuffer/depth-prepass passes without explicit declaration. Without manifest constraints, the engine cannot enumerate "all PSOs this game will need" at build time → can only compile lazily → first time each combination is hit → 100ms-2s stall → player sees hitches everywhere.

Our doctrine is the inverse, and it is the central design constraint of the renderer:

> **The set of PSOs a game needs MUST be statically derivable from the project. The engine refuses runtime shader generation.**

This is the trade-off Unreal made (knowingly) and Godot didn't. It's what separates "smooth shipped game" from "stutters everywhere".

What this means for game-dev flexibility — exactly what's allowed:

✅ Write any Slang shader, any vertex layout, any blend mode, any depth state
✅ Have thousands of materials authored in source / scene files / CLI
✅ Swap materials between objects dynamically (PSO already exists for either)
✅ Use advanced shading (clearcoat, sheen, hair, subsurface, custom passes)
✅ Modders can ship new materials — one-time compile per new material per machine

❌ Build shader source as a string at runtime and compile it
❌ Permute PSO state (blend, depth, formats) based on runtime conditions

In practice 99% of game devs never hit the constraint — nobody concatenates shader strings at runtime outside tech demos. The 1% who do can opt-in to Mechanism 1 below with a documented performance warning.

With that doctrine in place, **three independent mechanisms** make PSO compilation invisible to the player. They are NOT the same thing; conflating them is what makes most engine PSO docs hand-wavy.

### Mechanism 1 — Ubershader fallback (runtime safety net)

**Status (2026-07-13): the dedup + magenta-fallback + async-compile half shipped; the ubershader half
did not.** `ke_render_service::get_or_create_pipeline(params)` is the PSO authority every pass (in-tree
or a game's own — the core has no privileged passes, §7) calls every frame instead of
`ke_gpu_device::create_render_pipeline` directly:

- **Dedup**: keyed by a `PsoKey` hashing every field of `ke_gpu_render_pipeline_params` that affects
  the compiled object, in a `std.AutoHashMap` (O(1) lookup/insert — a fixed-size array + linear scan
  was tried first and was wrong: this is an arbitrary-equality keyed lookup, not the handle-indexed
  access pattern `CoreState`'s other tables use, and a small fixed cap can't even hold the ~400 PSOs
  §6.2 documents as a "typical project").
- **Never-stall**: a miss kicks an async compile and returns a **magenta fallback** immediately — built
  from the REQUESTER'S OWN vertex module + vertex layout + bind group layouts (only the fragment stage
  swaps to a trivial, arity-matched magenta shader generated as WGSL text at runtime), so it's correct
  for any pass uniformly, with no assumption about a specific vertex layout. Every subsequent request
  for that same key returns the fallback until the real PSO is ready, then the cached real PSO.
- **The async primitive is emulated, not native**: `wgpuDeviceCreateRenderPipelineAsync` is listed as
  unimplemented in wgpu-native (confirmed on trunk, not just the vendored release — it panics
  "not implemented" if called). `ke_gpu_device::create_render_pipeline_async` stays an
  implementation-agnostic ABI contract (`ke_render_service` has no idea which strategy backs it, nor
  would a browser backend need to); the webgpu backend specifically emulates it by dispatching the
  real, synchronous compile onto a caller-supplied `ke_scheduler` (falls back to synchronous
  compile-then-callback if no scheduler is wired — never hangs, just isn't async). Two real bugs were
  found and fixed building this: (1) every pass previously cached the PSO **handle** once at setup and
  reused it forever — since setup happens before the async compile finishes, that handle was
  permanently the magenta one; every pass now stores its full `ke_gpu_render_pipeline_params` and
  re-queries `get_or_create_pipeline` every `record()` call instead. (2) a dispatched `ke_task`'s
  memory is only freed by `wait()`, called exactly once — the compile job now retains a caller-added
  shader-module ref (since the pass's own `defer destroy_shader_module` fires before the async compile
  actually runs) and the device reaps/`flush`es dispatched tasks (`flush_pipeline_compiles`, called
  before `ke_render_service`'s own teardown — the same shutdown-ordering fix shape as
  `ke_runtime::flush_render`).
- **Manual verification seam**: `KE_PSO_ASYNC_DELAY_MS` (+ `KE_PSO_ASYNC_DELAY_BLEND_ONLY=1` to scope
  it to blend-enabled PSOs only, so an already-warm opaque scene stays correct while one new
  blend object visibly flashes magenta then resolves) — env-var gated, never engaged unless a
  developer sets it, not part of any shipped path. Confirmed working end-to-end this way: an object
  using a brand-new PSO renders magenta for the artificial delay, then swaps to correct shading, while
  pre-existing geometry using already-resolved PSOs is unaffected throughout.
- **Not built**: the ubershader (item 2 below) — every miss today falls back to magenta regardless of
  whether the request would have been ubershader-compatible. The distinction below (ubershader vs
  magenta) is still the target design; only the magenta path exists.

The **original design** (kept below as the as-yet-unbuilt target):

1. Look up the request in the ubershader compatibility map.
2. **Ubershader-compatible** (PBR forward, shadow caster, depth prepass, basic compute): render with the ubershader pipeline — a single large precompiled PSO that handles ~95% of common cases via dynamic branches and uniform-driven feature toggles. Visually nearly identical; ~10-20% slower per draw due to branchier shader.
3. **Not ubershader-compatible** (tessellation, mesh shader, RT pipeline, custom user passes): render with a **magenta placeholder PSO** — same vertex layout, fragment outputs `vec4(1, 0, 1, 1)`. Obviously wrong, debuggable, never silent.
4. In both cases: enqueue background compile on the worker pool.
5. Next frame: if compile finished, swap to real PSO.

**Ubershader vs magenta — when each fires**:

| Material type | Fallback | Player notices? |
|---|---|---|
| Standard PBR forward | Ubershader | No (looks identical, slightly slower for 1-2 frames) |
| Shadow casting | Ubershader | No |
| User shader (clearcoat / sheen / SSS) | Ubershader | Barely (effect missing for 1-2 frames) |
| Hair (Marschner) | Magenta | Yes (rare enough to flag) |
| Custom user pass | Magenta | Yes |

The ubershader itself is a build-time artifact: a Slang program parameterized over a large but fixed feature set, compiled into ONE PSO at build time, ships with the game.

**Doctrine**: ubershader is the *expected* fallback in dev iteration (modder content too). Magenta is the *debug visible* fallback that signals "something exotic happened that wasn't predicted". A shipped release game should never show magenta — Mechanism 2 catches everything ubershader can't cover.

### Mechanism 2 — Build-time PSO manifest (the doctrine made concrete)

Before the game ships, the engine extracts the complete PSO set from the project declaration. The CLI command `ke build manifest` walks the project and emits a manifest.

**What the CLI walks**:
- All `.material` files referenced anywhere in scenes / code / Project
- The set of passes each material participates in (declared per material via metadata, or defaulted per template — `IMaterial` → ForwardLit + Shadow + DepthPrepass; `IPostEffect` → fullscreen; etc.)
- All vertex layouts used (engine-defined: Static, Skinned, etc., plus user-declared)
- Render-target formats used by each pass (engine-declared per pass — `ForwardLit` uses `RGBA16F + D32F`)
- Variant flags (quality level, has-normal-map, etc., if any)

**The cartesian product** of (material × pass × vertex-layout × variant) → unique PSO keys.

**Manifest format** (TOML, deterministic, shippable):
```toml
[[pso]]
key = "water+forward_lit+static+v0"
shader_module = "shaders/water.slang"
entry_point_vs = "VertexMain"
entry_point_fs = "FragmentMain"
pass = "ForwardLit"
vertex_layout = "Static"
color_formats = ["RGBA16F"]
depth_format = "D32F"
blend = "Opaque"
depth = "TestLE_WriteOn"
primitive = "TriangleList"
sample_count = 1

# Typical project: 50 materials × 4 passes × 2 vertex layouts × 1 variant = 400 PSOs
```

**Generated**, never written by hand. Lives at `build/psos.manifest`. Regenerated on `ke build` whenever any material / scene / project file changes. **Ships in the install package**; the player's machine reads it on first launch.

**Refusing runtime shader generation isn't punitive — it's the trade that enables this manifest existing.** A game that needs runtime shader gen explicitly disables the manifest constraint per material and accepts Mechanism 1 fallbacks permanently for those materials.

#### 6.2.1 The feature-composition dimension is bounded by the game's declared settings, not the engine's feature set

The composable render features (shadow ⇄ `ILightVisibility`, IBL ⇄ `IIndirect`, dynamic lights ⇄ `ILightIterator` — §8.12/§9.8) each contribute a **variant** axis to a material's PSO. Naively that reads as a `2^N` explosion (shadow×ibl×lights×… → 8, 16, …). It is not, because of two facts:

1. **Feature composition is per render-module-instance, not per draw or per material.** A material never toggles shadows mid-frame; the whole module is created once (today via `ke_render_feature_params` — `enable_shadows`, `enable_ibl`, …) with a fixed composition. Every material in that module shares that one composition. So the live PSO space is `materials × 1`, linear, not `materials × 2^N`.
2. **A game may expose a *few* of those toggles as graphics settings** (e.g. "Shadows: On/Off" in an options menu, flipped at runtime). That does not reintroduce the full `2^N` — it introduces exactly the permutations *that game chose to expose*. The **game declares this set**, the engine never infers it or precompiles the universe. A game with a shadow toggle declares 2 shadow permutations; a game without declares 1. The manifest's "variant" dimension is therefore `materials × (the settings permutations the game itself declares)` — small, enumerable, owned by the game.

**Runtime toggle flow** (player flips "Shadows: Off" mid-session): if that permutation was declared and warm-compiled, the swap is instant. If it was *not* declared (an unanticipated combination), it is exactly the Mechanism-1 case — magenta for a frame or two while the specialization compiles in the background on the task scheduler, then cached on disk (Mechanism 3) so it is instant ever after. This is the ordinary "compiling shaders…" moment every game has, scoped to only the un-pre-warmed permutations.

**Current stand-in (debt).** The hand-authored `mat_test_flat.slang` / `_no_shadow` / `_no_ibl` / `_no_shadow_no_ibl` variants (+ their per-file `CMakeLists.txt` / `build.zig` entries) are the manual version of this generated variant axis, for the one built-in flat material at the 2×2 shadow×ibl corner. Each new toggle currently doubles that hand-written pile — which is precisely the signal that this dimension must become a Mechanism-2 build output (the game's declared settings permutations × its materials, emitted, not typed). Cluster/light opt-in was deliberately **not** hand-authored as a third axis for this reason; it waits on the generator rather than growing the manual matrix to 8.

### Mechanism 3 — Per-machine disk cache (PSO bytecode storage)

PSO compilation output is **driver-specific bytecode**. NVIDIA 555 compiled PSOs don't work on NVIDIA 556. RTX 4090 PSOs don't work on RTX 3060. Windows PSOs don't work on Linux. So compilation must happen on the player's machine, once per (driver version × GPU × OS) combination.

**Cache location**: `%LOCALAPPDATA%\KernelEngine\<game_id>\<engine_version>\<driver_hash>\` (Linux: `~/.cache/kernelengine/...`).
**Cache contents**: one binary file per PSO key, named by the key's hash. Bytecode blob + minimal metadata for validation.
**Driver hash**: hash of `(GPU vendor, GPU device, driver version, OS, OS version)`. Recomputed each boot; mismatch invalidates the cache.

**First launch flow** (per machine): read manifest → compute driver_hash → for PSOs missing from disk, show "Optimizing for your system (1/750)", compile on the worker pool (8-16 threads), write bytecode as each completes → done. Typical: 750 PSOs × ~500ms / 8 threads ≈ **~45 seconds, once per install + driver-update**.

**Subsequent launches**: manifest read → driver_hash matches → lazy load from disk as the renderer requests them (microseconds each — memcpy + create_pipeline from bytecode). Zero compilation, zero stalls.

**Driver update** → `driver_hash` mismatch → re-run first-launch flow (splash again, user understands why). **Engine update** → `engine_version` in the path → fresh cache.

### How the three mechanisms compose

```
BUILD-TIME (dev machine, `ke build`):  project → walk materials+passes+layouts →
    cartesian product → emit psos.manifest      (Mechanism 2)
                          ↓ manifest ships in install
FIRST LAUNCH (per machine × engine_ver × driver_hash):  read manifest → worker pool →
    compile every PSO not on disk → write bytecode → "Optimizing 750/750"   (Mechanism 3)
                          ↓ steady state
GAMEPLAY (every draw):  PSO requested →
    in RAM cache? → return (µs)
    in disk cache? → create_pipeline_from_blob (1ms) → cache in RAM
    neither (rare post-release; common in dev)? →
        ubershader compatible → ubershader + compile bg
        exotic → magenta placeholder + compile bg                            (Mechanism 1)
```

| Mechanism | Owns | Runs when | Scope |
|---|---|---|---|
| 1 — Ubershader / magenta fallback | "we don't stall, ever" | Every draw that misses cache | Per draw |
| 2 — Build-time manifest | "we know what PSOs we need" | Every `ke build` | Per project, per build |
| 3 — Per-machine disk cache | "actually compiled bytecode" | First launch, driver update | Per machine, engine_ver, driver |

### 6.4 Operational modes

- **Dev iteration**: manifest may be stale; disk cache partial; Mechanism 1 carries the load (miss → ubershader → bg compile → swap). Hot reload of `.slang` invalidates affected PSO cache entries. Goal: never break the iteration loop.
- **Beta / playtest**: manifest generated + shipped; first launch compiles (~45s); Mechanism 1 catches gaps (logged as warnings).
- **Shipped release**: manifest complete; first launch warms disk cache; Mechanism 1 only fires for modder content. Goal: zero unexpected stalls, ever.

### 6.5 Cache invalidation

| Event | Result |
|---|---|
| Edit a `.slang` (dev) | RAM: invalidate every PSO referencing it. Disk: invalidate only if compiled bytecode hash changed. |
| Driver update (player) | `driver_hash` mismatch → fresh first-launch flow |
| Engine version update | Cache dir changes (`<engine_ver>`) → fresh first-launch flow |
| Game update (new materials) | Manifest changes; new PSOs missing → compile next launch (only the diff) |
| Mod installs new material | Manifest unchanged; runtime PSO miss → Mechanism 1 + bg compile, then added to disk cache |

### 6.6 Implementation breakdown (each mechanism is its own project)

| Phase | Mechanism | Scope |
|---|---|---|
| Initial | Mechanism 1 (ubershader + magenta) | Make dev iteration painless. Ubershader covers PBR forward + shadow + depth prepass; magenta for the rest. |
| +1 | Mechanism 3 (disk cache + driver hash) | Bytecode persists across launches; RAM cache in front. |
| +2 | Mechanism 2 (build-time manifest) | `ke build manifest` CLI verb; first-launch compile driven by manifest. |
| +3 | Polish | Manifest coverage metrics, compile-budget reporting, driver-update UX. |

Mechanism 1 alone is enough to ship M1-M2 demos. Mechanism 3 before any non-trivial game. Mechanism 2 before shipping any release game.

---

## 7. No render-graph object — the runtime IS the graph

The V1 render graph (`render_graph.h` with `add_pass` / `compile` / `execute`) **is eliminated in V2.** Its two jobs split cleanly, and only one of them was ever render-specific:

- **Ordering** (topological sort over the pass DAG, barrier sequencing) → **moves to the runtime.** A render pass is a plain runtime system; the runtime's wave-builder already orders systems by their access list (write-before-read on shared keys). There is no Kahn sort in the render layer — the same dependency solver that orders sim systems orders render passes.
- **Resource management** (transient render-target allocation + aliasing, barrier insertion, name→view resolution) → stays render-specific, and becomes the **render core** service (§5), not a graph object.

### 7.1 Render resources are tag-component cids

The mechanism that lets the runtime order passes by *texture* dependency — not just by ECS-component dependency — is that **each render resource is registered as a zero-size tag component** in the ECS. `ke_render_service_declare("scene_color", …)` calls `ke_ecs_component_register(reg, "rg.scene_color", 0)` and gets back a real `ke_component_id`. The cid has no per-entity storage; nobody ever calls `ke_system_ctx_get` on it. It exists purely as a dependency key.

A pass declares its resource reads/writes as access-list entries alongside its component reads:

```
add_pass "forward":  access = [ {Camera,R},{Mesh,R},{Light,R}, {rg.scene_color,W},{rg.depth,W} ]
add_pass "bloom":    access = [ {rg.scene_color,R}, {rg.backbuffer,W} ]
```

The wave-builder sees `forward` WRITE `scene_color` and `bloom` READ `scene_color` → orders forward before bloom, by the identical write-before-read rule it applies to components. **Zero runtime changes**: the runtime's dependency solver is generic over cids and never distinguishes "real component" from "render-resource token".

### 7.2 A pass is a plain runtime system

```c
runtime->register_system(rt, &(ke_runtime_system_params){
    .name = "forward", .phase = KE_PHASE_UPDATE,
    .access_list = forward_access, .access_count = 5,
    .pinned_thread = 0,                 // unpinned → wave dispatcher places it (§9.7)
    .user_data = &forward_pass,         // holds render_core* + its ke_pass_io
    .execute = forward_execute,
});

void forward_execute(ke_system_ctx *ctx, void *user, float dt) {
    forward_pass *p = user;
    ke_render_pass_ctx *pc = ke_render_service_begin_pass(p->core, ctx, &p->io);
    ke_gpu_render_pass *rp = pc->begin_render(pc);     // L4 recording object
    /* read components via ctx, resolve resource→view via pc, issue draws */
    rp->end(rp);
    ke_render_service_end_pass(p->core, pc);
}
```

`begin_pass` resolves the pass's declared resources to live `ke_gpu_texture_view`s, sets up the target attachments, and tracks each resource's state to insert the needed barrier at the wave boundary (producer in wave K, consumer in wave K+1). Because the runtime guarantees same-wave passes have disjoint access, the render core's per-resource state is touched by one pass at a time — **lock-free without trying to be.**

**Extensions** (ray tracing, mesh shaders) are reached through the same context: `void *rt = pc->query_ext(pc, KE_GPU_EXT_RAYTRACING); rt->dispatch_rays(rt, pc->encoder(pc), &p);`. This is not layer-skipping — extensions are the open frontier L5 cannot pre-wrap (§4.5); the context supplies the encoder and resources the extension call needs. L5 wraps the universal core ergonomically (≈95%); extensions stay raw-but-reachable (the unbounded tail). That is what "infinite power without touching L3 core" means.

This is **locked**. The `render_graph.h` object, its `compile()`/Kahn sort, and the `ke_render_pass_record_fn` / `get_renderer()` / frame-packet context are V1 legacy (bgfx renderer) — not part of V2.

---

## 8. Shader pipeline — Slang as canonical source

### 8.1 Choice rationale

- **Modules + interfaces + generics** at the shader level — engine ships `ke.surface` declaring `interface IMaterial { void vertex(inout VertexInfo); void fragment(inout SurfaceState); }`. Users implement the interface; Slang's generics instantiate the engine's entry point with the user impl.
- **One source → all backends**: SPIR-V (Vulkan), DXIL (D3D12), MSL (Metal). Slang ships official cross-compilers; we don't write any of this.
- **Reflection**: Slang exposes its reflection API — PSO layout, bind group bindings, push constants come from the same source, no hand-maintained sidecars.
- **AAA-validated**: NVIDIA, UE5, others use Slang in production.

Shaders live in `src/shaders/` — `ke.slang` umbrella + `ke/` submodules (`globals`, `samplers`, `math`, `noise`, `pbr`, `surface`) + `materials/` (carried over from the previous branch; relogic on first impl, structure kept).

### 8.2 Build integration

`scripts/compile_shaders.py` (today: `shaderc` for bgfx `.sc`) gains a parallel path: `*.slang` → `slangc` → `.spv`/`.dxil`/`.msl` under `build/.../shaders/compiled/<backend>/`. Renderer V2 loads bytecode via `device->create_shader_module(blob, &err)`. Both pipelines coexist during migration.

### 8.3 Shader author DX

**Goal**: a game dev writes one `.slang` file, sees parameters in the editor, gets correct depth/shadow/prepass for free, never touches a binding number or PSO descriptor.

```hlsl
// game/materials/water.slang
import ke;          // the only import you ever need

struct WaterMaterial : IMaterial {
    [editor(label="Normal Map")]
    Texture2D normalMap;

    [editor(label="Wave Speed", range={0.0, 5.0})]
    float waveSpeed = 1.0;

    void vertex(inout VertexInfo v) {
        v.position.y += sin(v.position.x * 0.1 + ke_time * waveSpeed) * 0.5;
    }
    void fragment(inout SurfaceState s) {
        float3 n = normalMap.Sample(ke_samp_linear, s.uv).xyz * 2 - 1;
        s.normal  = mul(s.tbn, n);
        s.albedo  = float3(0.1, 0.3, 0.5);
        s.roughness = 0.05;
    }
}
```

This is the **complete** file for a lit, wave-animated, normal-mapped material that renders correctly in ForwardLit, DepthPrepass, and ShadowCaster. No PSO declaration, no binding index, no pass registration, no sidecar required.

**`import ke;`** re-exports every engine module the author might need:

| Sub-module | What it provides |
|---|---|
| `ke.globals` | `ke_time`, `ke_dt`, `ke_view`, `ke_proj`, `ke_cameraPos`, `ke_viewportSize` |
| `ke.samplers` | `ke_samp_linear`, `ke_samp_nearest`, `ke_samp_aniso`, `ke_samp_shadow` |
| `ke.math` | `remap`, `pow_safe`, `luminance`, `pack_normal`, rotation helpers |
| `ke.noise` | `simplex2`, `simplex3`, `fbm`, `voronoi` |
| `ke.pbr` | `GGX`, `Smith`, `Schlick`, `DFG_LUT`, `SampleIBL` |
| `ke.surface` | `SurfaceState`, `VertexInfo`, `LightInput`, `LightContribution`, the template interfaces |

**`@editor` annotations** expose parameters into the material editor's inspector without a sidecar. Supported widgets: `texture`, `color`, `hdr_color`, `vector`, `curve`; absent a hint, the editor infers from type. Reflection derives the bind-group layout from struct field order — the layout *is* the reflection output, no `[[vk::binding(N)]]`.

**`ke shader new <template> <name>`** generates a stub `.slang` + `.material.toml` with the correct interface and method signatures.

**Hot reload (dev)**: the watcher monitors `materials/` for `.slang` changes, triggers an incremental `slangc` compile, invalidates the affected PSO keys; Mechanism 1 displays while the new pipeline compiles. No restart.

### 8.4 Template catalog — one interface per authoring archetype

`IMaterial` is one of a small fixed set of **shader templates** the engine ships. A template is an `interface` in an engine `.slang` module; the author writes a `struct` implementing it. Templates are the *only* sanctioned authoring surface — a game dev never writes a raw entry point, never declares a PSO, never touches a bind-group index. The doctrine is **one template per archetype that is genuinely universal across games**; the exotic long tail (hair, cloth, caustics, decals) ships as *plugin templates* that refine an engine template (8.9).

| Template | Module | What the author fills in | Engine passes that consume it |
|---|---|---|---|
| `IMaterial` | `ke.surface` | `vertex(inout VertexInfo)`, `fragment(inout SurfaceState)`, optional `light(surface, l) -> LightContribution` — lit PBR surface | ForwardLit, DepthPrepass, ShadowCaster, (future GBuffer) |
| `IUnlitMaterial` | `ke.unlit` | `vertex`, `fragment(inout UnlitState)` — color out, no lighting | UnlitForward (+ ShadowCaster if `castsShadow`) |
| `IPostEffect` | `ke.post` | `fragment(in PostInput) -> float4` — fullscreen | any fullscreen graph node (tonemap, color-grade, FXAA, bloom composite) |
| `ISkyboxMaterial` | `ke.sky` | `fragment(in SkyInput) -> float3` — per view-ray | Skybox (rotation-only view, depth-test LEQUAL, no write) |
| `IComputeKernel` | `ke.compute` | `main(in DispatchInput)` | any compute graph node (cull, particle sim, blur, histogram) |
| `IParticleKernel` | `ke.particle` | `start(...)` + `process(...)` — GPU particle sim | ParticleSim + ParticleUpdate compute passes, result drawn by a draw pass |
| `IFogVolume` | `ke.fog` | `fog(in FroxelInput) -> FogContribution` — density + scattering per froxel | VolumetricFog froxel pass, composited after ForwardLit |

Seven templates cover ~98% of what games author. Adding an eighth core template is a deliberate doctrine decision, not a convenience — the bar is "every serious game needs this archetype and it cannot be expressed by refining an existing one."

### 8.5 `ke.surface` — the `IMaterial` contract in full

Frozen at the template's semver.

**`VertexInfo`** — the vertex stage's mutable view. The engine owns the MVP transform and interpolation; the author only *perturbs*.

```hlsl
struct VertexInfo {
    // ── Inputs (read; populated from the bound vertex buffer per its layout) ──
    float3 position;      // object space
    float3 normal;        // object space
    float4 tangent;       // object space; .w = handedness
    float2 uv0;
    float2 uv1;           // zero if no second channel
    float4 color0;        // (1,1,1,1) if absent
    uint4  boneIndices;   // present only in the SKINNED variant; reading in non-skinned is a compile error
    float4 boneWeights;
    // ── Author-writable (perturbation) ──
    // Mutate position/normal/uv for wave, wind, vertex animation. Leave untouched for a static mesh.
    // The engine reads these back AFTER vertex() and applies world/view/projection itself.
};
```

**`SurfaceState`** — the fragment stage's output. The author writes the surface; the consuming pass's lighting model reads it.

```hlsl
struct SurfaceState {
    // ── Read-only context (engine-populated before fragment()) ──
    float2 uv; float2 uv1; float4 color;
    float3 worldPos;
    float3x3 tbn;         // tangent→world basis, for normal-map decode
    // ── Author-writable surface (PBR metallic-roughness) ──
    float3 albedo;        // default (1,1,1)
    float  metallic;      // default 0
    float  roughness;     // default 0.5
    float3 normal;        // world space; default = geometric normal
    float3 emissive;      // default 0
    float  ao;            // default 1
    float  alpha;         // default 1; blend variant honours it
    // Extended-PBR lobes — writable ONLY when the matching capability variant is enabled (8.7).
    // Untouched ⇒ lobe disabled, zero cost.
    float  clearcoat; float clearcoatRoughness; float sheen; float anisotropy;
};
```

**Engine globals** — a read-only uniform block referenced by name without declaration, bound by the pass, identical across templates: `ke_time`, `ke_dt`, `ke_view`, `ke_proj`, `ke_cameraPos`, `ke_viewportSize`.

Light data is **not** in this block. The author never loops lights — that's the consuming pass's lighting model (ForwardLit clustered loop) reading `SurfaceState` *after* `fragment()`. Keeping lights out of the material contract is what lets the same `WaterMaterial` run unmodified under forward, deferred, or a future clustered-visibility pass: the material describes a surface, not how it's lit.

**`light()` — optional per-light override.** By default the pass evaluates each light with the engine's PBR GGX model (Schlick-GGX BRDF + Smith geometry + Schlick Fresnel). A material may override:

```hlsl
LightContribution light(SurfaceState surface, LightInput l);  // optional; absent ⇒ engine PBR GGX

struct LightInput {
    float3 direction;     // world-space, FROM surface TO light
    float3 color;         // pre-multiplied by intensity
    float  attenuation;   // range/spot falloff applied; 1.0 for directional
    float  shadow;        // [0,1]; 1 = fully lit
    float3 N, V, H;       // convenience reads (post fragment())
    float  NdotL, NdotV, NdotH;  // saturated
};
struct LightContribution { float3 diffuse; float3 specular; };
```

The pass calls `light()` once per visible light per pixel; when not implemented, the loop body is the engine GGX. Implementing it does **not** change how many lights the scene supports, how shadows work, or which passes the material joins — those are orthogonal.

The other templates' context types (`UnlitState`, `PostInput`, `SkyInput`, `DispatchInput`, `ParticleState`/`ParticleSpawnInput`/`ParticleUpdateInput`, `FroxelInput`/`FogContribution`) follow the identical doctrine — read-only engine-populated context, a narrow author-writable surface, engine globals in scope — spec'd in full when each template's first impl lands.

### 8.6 Template ↔ Pass — the relationship that makes it compose

The load-bearing distinction, the one most engines blur:

- A **template** (`IMaterial`, …) is an *authoring surface*. The author fills it in once.
- A **pass** (§7 render-graph node) is an *execution unit*: attachments + load/store + a pipeline + a dispatch over a draw set. Authored by engine, plugin, or game.

A single material instantiates into **many** passes. `WaterMaterial : IMaterial` produces — at build time — a ForwardLit PSO, a DepthPrepass PSO, and a ShadowCaster PSO. Three pipelines, one authored surface. Each engine pass shader `import`s the material and calls `vertex()` / `fragment()` where its program needs the surface:

- **ForwardLit** calls `vertex()` then `fragment()`, then runs the clustered lighting loop over the `SurfaceState`.
- **DepthPrepass** calls `vertex()` only (it needs the possibly-perturbed position), writes depth.
- **ShadowCaster** calls `vertex()` from the light's POV, writes depth to the shadow atlas.

The author wrote `vertex()` once; it ran in three passes. **That** is why perturbation (wave, wind, skinning) stays correct in shadows and depth without the author thinking about it.

Two kinds of pass: **template-consuming** passes are generic over a template (`ForwardLitPass` runs any `IMaterial`) and contribute the cartesian multiplier in the manifest; **self-contained** passes carry their own shader and consume no template (a bloom downsample, an FXAA resolve) and contribute one PSO each.

Which passes a material participates in is **declared by the material**, not inferred — default per template (`IMaterial` ⇒ ForwardLit + DepthPrepass + ShadowCaster), overridable in metadata. The manifest reads these declarations; nothing is discovered at runtime.

### 8.7 Variants — generics first, specialization constants second, `#ifdef` banned

1. **Slang generics / link-time specialization (default).** Vertex-layout variants (STATIC vs SKINNED), capability lobes (clearcoat on/off), quality tiers — generic parameters specialized at compile time. Each specialization is a distinct, fully-reflectable program; the manifest enumerates them. This is the mechanism for anything that changes the PSO's shape.
2. **Specialization constants (runtime-cheap toggles).** For a boolean the driver can fold and that genuinely flips at runtime (a debug-view mode, a global quality switch). Used sparingly.
3. **`#ifdef` / preprocessor — banned.** It defeats reflection, splits source into untrackable combinatorial soup, and is exactly the path that makes other engines unable to derive their PSO set statically. Incompatible with §6's "PSO set MUST be build-time enumerable". No engine or game shader uses it.

Variant axes are **declared** (8.8) so the manifest takes the cartesian product. An undeclared variant cannot exist — no runtime path conjures a new PSO shape.

**Canonical render modes** — reserved variant names with engine-defined semantics, declared in metadata or via `[mode(...)]`:

| Mode | Effect |
|---|---|
| `unshaded` | Skips lighting; `fragment()` output written directly. No ForwardLit; still in DepthPrepass by default. |
| `double_sided` | Disables back-face culling; engine flips geometric normal for back faces. |
| `depth_prepass_only` | DepthPrepass + ShadowCaster only; no color pass. Occluders. |
| `no_depth_write` | Depth write disabled (glass, particles, decals). Implies queue ordering. |
| `no_shadow_cast` | Opts out of ShadowCaster. Small/alpha-tested meshes that cause acne. |
| `alpha_blend` | Blending on; `SurfaceState.alpha` honoured; drawn in a separate transparency pass after opaques. |
| `alpha_scissor` | Alpha-test discard; order-independent, compatible with DepthPrepass. `[mode(alpha_scissor=0.5)]`. |

Not free-form strings — they map to concrete PSO state bits and pass-membership rules. An unknown mode name is a compile error. The exotic long tail belongs in plugin-declared modes.

### 8.8 Authoring flow — discovery, metadata, manifest, runtime

Common spine: **author `.slang` → discovered → metadata declares passes+variants → manifest enumerates PSOs → slangc compiles + reflection emits layout → PipelineCache serves at runtime.**

**Discovery** by convention — the project's `materials/` tree + any `res://` path referenced by a `.material` asset + explicit registration for plugin shaders.

**Metadata** — two equivalent sources:
- *Option A — `[editor]`/`[mode]` annotations only.* The build tool reads the Slang source, extracts attributes via reflection, infers template + pass-set + variant axes from interface conformance. ~90% of materials, zero sidecar.
- *Option B — `<name>.material.toml` sidecar* (when you need overrides / explicit pass lists / non-default variants):

```toml
[material]
template = "spatial"                         # inferred from : IMaterial if absent
passes   = ["ForwardLit", "ShadowCaster"]    # opt out of DepthPrepass
modes    = ["double_sided", "alpha_blend"]
[material.variants]
vertex_layouts = ["Static", "Skinned"]
features       = ["clearcoat"]
```

The sidecar wins on any field it specifies; absent fields fall back to annotation inference. **It is an override file, never required.**

**Manifest** reads every material's metadata, emits the cartesian product as PSO keys. **Compile + reflect**: `slangc` per `(material, pass, variant)`; Slang reflection emits vertex layout, bind-group layout, push-constant ranges. **Runtime**: `MaterialBinding` (§5.4) maps a `Material` instance + current pass to a PSO key, fetches from `PipelineCache`, builds the bind group. Cache miss in dev → Mechanism 1 fallback.

### 8.9 Extending the template set — plugin templates, not core bloat

When a game needs an archetype the core seven don't cover — hair, water caustics, anisotropic car paint, screen-space decals — the answer is a **plugin template**, never a new core interface:

```hlsl
// KernelEngine.Render.Hair ships ke_hair.slang
import ke.surface;
interface IHairMaterial : IMaterial { /* + strand params */ }
```

The plugin owns both halves: the refined template *and* the pass(es) that consume it. It registers its passes with the render graph like an engine pass (§9), declares its variants for the manifest, ships as `KernelEngine.Render.<Feature>`. The core engine never grows a hair branch; a game that doesn't render hair never compiles a hair PSO.

### 8.10 What §8 locks

Locked now (shader-authoring contract, frozen at template semver): the **seven core templates** + plugin-template rule; the template↔pass relationship; `IMaterial`'s `VertexInfo`/`SurfaceState`/engine-globals contract (lights never in it); the `light()` hook contract; variant doctrine (generics → spec-constants → `#ifdef` banned); canonical render modes; the authoring spine; `import ke;` umbrella; `[editor]` annotations; `ke shader new`.

Pinned per impl phase: full field lists for the non-`IMaterial` context types; exact Slang generic signatures for vertex-layout/feature axes; the `.material.toml` grammar; the `ke shader new` CLI ship point.

**Status (2026-07-02):** first vertical slice shipped for the flat case — `ke.surface`'s `SurfaceState` carries the read-only context fields (`uv`/`worldPos`/`tbn`) the pass body needs; `forward_lit.slang` is the engine `ForwardLit` pass, generic over `T : IMaterial`, calling `material.vertex()`/`material.fragment()` before running the same Cook-Torrance/clustered-light/IBL body as `forward.slang`; `mat_test_flat.slang` is a hand-written material conformance (stand-in for future `ke shader new` codegen) proving the composition compiles to valid WGSL with byte-identical set-0/1/2/3 bind-group + vertex layouts to `forward.slang` — zero C ABI / C# binding change. `forward.slang` stays wired as the fallback-of-record; nothing deleted. Not yet shipped: reflection-driven variable material layouts, `.material.toml`, `ke shader new`, the remaining six templates, the contribution-interface seam (§8.11–§8.13), and Mechanisms 2/3 below.

**Status (2026-07-12): the real authoring flow shipped — no longer a scaffold.** A material is now genuinely just `src/shaders/materials/<name>.slang` (or any directory in `KE_MATERIALS_DIRS`, a *list* so a downstream project's own materials directory coexists with the engine's rather than replacing it) — a lone `struct X : IMaterial`, no entry point, no pass import, no per-pass hand-duplication. `cmake/CompileMaterialShaders.cmake`'s `ke_compile_material_shaders` (called from each `IMaterial`-consuming pass's own `CMakeLists.txt`) discovers every material across those directories and, via `scripts/generate_material_wrapper.py`, generates the (material × pass) wrapper that binds the material's `IMaterial` conformance into that pass's generic entry points — this is exactly the manifest-codegen role §8.8 describes, just CMake-driven rather than a standalone `ke build manifest` CLI. `create_material` takes a `shader` **name** (the file stem) instead of a numeric `shader_variant`; `ke_render_core::load_shader(core, name, stage, &err)` resolves `"<shader>.<pass>"` to the compiled artifact by asking `device.shader_language()` for the format — no pass names a path or a format, closing the §6.5/§8.5 debt these sections used to flag. Three materials prove the three categories: `materials/standard.slang` (engine default, renamed off the `test_flat` placeholder), `materials/stripes.slang` (2nd engine-shipped material, genuine fragment-shader difference, the §6 Mechanism 1 distinct-PSO proof), and `examples/csharp/03_pbr_directional/materials/checker.slang` (owned by the *example*, outside `src/shaders/` entirely — proves a downstream project authors its own `IMaterial` without touching the engine tree). Verified rendering correctly (screenshot-diffed against expected pattern per material). **Still not shipped**: reflection-driven variable material layouts (every material is still stuck on `forward_common.slang`'s one fixed UBO + 2-texture bind-group shape — a material cannot yet declare its own parameters), `.material.toml` (confirmed still optional/never-required, not yet needed), `ke shader new`, the remaining six templates (§8.4 — only `IMaterial` has a consuming pass; `IPostEffect`/`ISkyboxMaterial` are the cheapest next since `tonemap`/`skybox` already have the single-shader shape the current mechanism handles), plugin templates (§8.9), and a C#-only material-authoring flow (today adding a material directory still means editing the engine's root `CMakeLists.txt` — a game dev with no CMake in their own workflow has no path yet; flagged, deferred).

### 8.11 The three composition seams — material, feature, pass

The `IMaterial` seam (§8.4–§8.6) is **one** of three. Naming all three is what makes a *dumb* forward — one that does not know shadows, clustering, IBL, or any pass — a precise design goal rather than an aspiration.

| # | Seam | Interface | Who implements | Who consumes |
|---|---|---|---|---|
| 1 | **user ↔ pass** | `IMaterial` (surface) | game material shader | a shading pass |
| 2 | **feature ↔ pass** | contribution interfaces (§8.12) | a feature module (shadow, IBL, clustering) | a shading pass |
| 3 | **pass ↔ core** | the pass *is a runtime system* (§7, §9.2) | a render module | nothing — the core owns no pass |

The load-bearing consequences:

- **The core (L5) owns no pass.** `ke_render_service` is resource registry + pass context + transient pool + barriers (§5, §7). `forward` is a system a module registers — exactly as `shadow` or `tonemap` is. Forward is **not** privileged; `render_module.zig` is now a thin composition-root aggregator, not a pass owner — each pass ships as its own physical plugin (§9.8).
- **The shading math is a shared library, not a pass.** `ke.pbr` (Cook-Torrance BRDF), `SurfaceState`, and the contribution *interfaces* live in the core shader library (`ke.*`). Whichever pass performs shading — a forward fragment, or a deferred-lighting fullscreen pass — calls the **same** library. No pass owns lighting; lighting is a library the shading pass invokes.
- Three tiers, each ignorant of the tier above the seam:
  - **Core shader library** (`ke.*`): math, BRDF, `SurfaceState`, contribution interfaces. Knows no feature, no pass.
  - **Feature components** (shadow / IBL / clustering): each implements one interface, knows only itself.
  - **Passes** (`forward`, `gbuffer`, `deferred_lighting`, `shadow_depth`, `tonemap`, …): each is a module/system that composes `{material} × {enabled features}` and dispatches. Knows the *structure* of its shading (inline vs fullscreen-from-G-buffer), never the *features*.

### 8.12 Contribution interfaces — the feature ↔ pass seam

A shading pass is authored **generic over abstract contribution hooks**, each with a no-op default. The pass source names the *abstraction*, never the *feature*.

```hlsl
// core library (ke.*) — declares the seam, implements nothing feature-specific
interface ILightVisibility { float visibility(LightInput l, SurfaceState s); }  // shadow
interface ILightIterator   { void  forEachLight(SurfaceState s, inout Accum a); } // clustering
interface IIndirect        { float3 ambient(SurfaceState s); }                    // IBL / ambient

struct FullyLit  : ILightVisibility { float visibility(LightInput l, SurfaceState s) { return 1.0; } }
struct SimpleLoop: ILightIterator   { /* iterate every light, no culling */ }
struct NoIndirect: IIndirect        { float3 ambient(SurfaceState s) { return float3(0); } }
```

The forward fragment computes `radiance *= vis.visibility(l, s)` — `vis` is a generic parameter. **Forward's source has zero `shadow` references.** The shadow module supplies `struct ShadowMapVisibility : ILightVisibility { /* sample the shadow map */ }`, linked at composition time **only when the shadow module is present**; otherwise `FullyLit` links and the shadow-map binding does not exist in the layout at all. Clustering supplies an `ILightIterator` (froxel lookup) vs the default `SimpleLoop`; IBL supplies an `IIndirect`. This is the mechanism the `IMaterial` slice already proved (`slangc` generics → valid WGSL) and is precisely what Slang's "shader components" was designed for.

**The access-list follows the linked feature set.** Enabling the shadow module adds three things that appear and disappear *together*: (a) the `shadow_depth` pass that produces the shadow map; (b) the `ShadowMapVisibility` impl linked into the shading program; (c) the `rg.shadow_map` **read** on the shading pass's access list (so the wave-builder orders shadow-depth before shading — §7.1). Without the module, none of the three exist; the shading pass declares no shadow dependency.

**The honest execution nuance.** "Forward doesn't know shadows" is total at the **source / authoring** level. At the **linked-binary** level the visibility sampling runs inside forward's fragment — because forward shading is where `light × visibility` happens — but it got there by *composition*, not *authoring*. Two distinct pieces wrongly both called "shadow": the shadow-map **generation** (`shadow_depth` pass) is a fully independent pass forward never references; only the shadow **sampling** is a component linked into shading. Removing even the sampling from forward's binary would require a screen-space shadow-mask pass (extra pass + bandwidth, poor with many shadowed lights) — the component-linked path is the standard, cheaper answer and what Slang optimizes for.

### 8.13 Pass as module — forward is not special; forward ↔ deferred

Because the core owns no pass (§8.11), swapping the renderer's topology is swapping which pass-modules are registered — not touching the core.

- **`SurfaceState` is the topology pivot.** The material's `fragment()` always writes the same `SurfaceState`. **Forward**: the pass reads it and shades inline. **Deferred**: a `gbuffer` pass encodes `SurfaceState` into the G-buffer MRTs; a `deferred_lighting` pass decodes it and shades using the **same** shading library + contribution interfaces (§8.12). §8.6 already lists GBuffer as an `IMaterial`-consuming pass. Neither forward nor deferred knows shadow; both call the shared shading library, and shadow plugs into the hook.
- **The deferred G-buffer limit is universal, not ours.** *Any* deferred renderer serializes the surface into a bounded G-buffer, so it cannot carry an arbitrary `SurfaceState`: extended lobes (clearcoat, sheen, anisotropy, subsurface) either fatten the G-buffer (bandwidth/memory), require a *shading-model ID* that reinterprets channels (Unreal's approach; generalized by Substrate/Strata), or are unsupported in deferred. Our architecture neither worsens nor fixes this — it makes the seam explicit: the `gbuffer` pass is the encode/decode point, and "which `SurfaceState` fields survive" is a property of the G-buffer-encoder variant. Forward carries the full `SurfaceState` because it shades inline, no serialization.
- **Deferred-clustered is possible; the cull is largely shared.** Clustered light-binning (froxel cull, Olsson 2012) is topology-independent — the **cull compute pass is shareable** between forward+ and clustered-deferred. The difference is the per-pixel froxel **lookup**: forward reads depth from the rasterized fragment, deferred reads it from the G-buffer; the froxel-index math is identical. Deferred additionally *may* run a tighter **tile depth-bounds** cull (it has the full depth buffer) that forward+ typically cannot. So `ILightIterator` impls can be pass-aware, and cull passes are swappable modules producing the same light-list resource.
- **"Render nothing" is register no draw passes.** The core and runtime do nothing by themselves; the only quasi-mandatory plumbing is the frame bracket (`begin_frame` / `clear` / `end_frame` / present), serialized via the backbuffer tag-cid (§9.7), and only when a swapchain exists.

**Status (2026-07-02): design-level, unbuilt.** No contribution interface, no deferred pass, no pass-aware iterator exists yet. The `IMaterial` generics slice (§8.10) de-risks the composition mechanism; §8.11–§8.13 are the doctrine the module decomposition (§9.8) builds toward. Deferred is **not** a near-term deliverable — it is documented so the pass↔core seam is proven sound against a second topology, keeping forward from re-privileging itself.

**Status (2026-07-12): shipped — stale note above kept for history.** `gbuffer` + `deferred_lighting` are both real, physically-split plugins (§9.8); the contribution-interface seam (§8.12) is production-wired for shadow, IBL, and clustering, each reading a neutral-default resource when its producing feature is absent rather than the pass knowing the feature exists. Both `gbuffer.slang` and `transparent_forward.slang` are generic over `T : IMaterial`, and both are now real (material × pass) consumers of the authored-materials mechanism (§8.10's 2026-07-12 status note) — the same `standard`/`stripes`/`checker` materials resolve into both topologies. Verified: `13_full_scene` (deferred opaque path + forward transparency combined) renders correctly.

### 8.14 End-state — deferred **+** forward, never deferred **vs** forward

The mature real-time pipeline is not a choice between topologies; it is a **hybrid**, and every AAA engine converges on it:

- **Opaque** shades through **deferred** (classic G-buffer *or* a visibility buffer — thin ID+barycentrics re-fetched at shade time, Nanite-style). Deferred's real value is **decoupling visibility from shading** (shade once per pixel; enables decoupled shading rate, micro-poly geometry), not merely "more lights" — with a shared clustered cull, forward+ scales to many lights too.
- **Transparency** shades through **clustered forward** — unavoidable: a G-buffer / visibility buffer stores exactly one surface per pixel, so N-layer order-dependent blending cannot be represented in deferred. This is universal.
- **Both halves share the clustered light cull** (§8.13) and, crucially, **the same materials and the same shading library** — the opaque deferred-lighting pass and the transparent forward pass each consume one `IMaterial`'s `SurfaceState` and the same `ke.pbr` + contribution interfaces.

**What we guarantee (the invariants that keep the hybrid reachable). The opaque deferred half is built; the transparent forward half is specified in §8.15:**

1. **Materials never assume a shading topology** — always write `SurfaceState`, never shade themselves. One material must be able to instantiate into forward-shade, gbuffer/vis-buffer write, deferred-lighting, *and* transparent-forward.
2. **The shading library + contribution interfaces never assume they are inside a forward pass** — the same code runs in a forward fragment and a deferred-lighting fullscreen dispatch.

Hold these two and the hybrid is later a matter of *registering more pass-modules* (gbuffer / vis-buffer / deferred-lighting / transparent-forward) — the core (§8.11) never changes.

**Left deliberately open (guarantee the seam, not the form):**

- **Which deferred form** — classic fat G-buffer vs visibility buffer — is undecided. We commit to neither; the material/shading contract must not presume either. Picking one belongs to whenever deferred is actually built.
- **`SurfaceState` stays evolvable (semver, §8.5)** as the plug point where a richer surface representation lands later. The industry answer to "a fixed G-buffer can only carry one shading model per pixel" is a composable layered-BSDF material with variable-footprint encoding — **Unreal's Substrate (née Strata)**. Substrate generalizes *surface expressiveness in deferred* only; it does **not** address transparency (still forward) and is **not** the hybrid itself. It is a future enrichment that plugs into the `SurfaceState` seam — so the contribution interfaces must be able to migrate from "here is albedo/metallic/roughness" to "evaluate this BSDF" without breaking passes. Not near-term; recorded so the seam is not frozen shut.

### 8.15 Transparency — the forward half, and where the forward pass closes

The deferred half of §8.14 shipped: `gbuffer` encodes, `deferred_lighting` decodes and shades. This section
locks the transparent half. It is the *last* structural decision the forward pass needs, and the intent is
to close forward here and not reopen it.

#### 8.15.1 Bucketing — `alpha_mode` on the material, never a tag on the entity

A surface's transparency is a property of the **material**, not of the entity instancing it. Two entities
sharing a material must never disagree about which pass shades them. The material therefore carries a
three-valued mode, aligned with glTF 2.0 `material.alphaMode`, Unreal's *Blend Mode*, and Unity's
*Surface Type*:

| `alpha_mode` | Pass | Depth | Notes |
|---|---|---|---|
| `OPAQUE` | gbuffer | write | The default. Alpha channel ignored. |
| `MASK` | gbuffer | write | Opaque with `discard` below `alpha_cutoff`. **Not** blending — foliage, fences, chain-link. |
| `BLEND` | transparent forward | test only | The only mode that leaves the G-buffer. |

Rejected alternatives, recorded so they are not re-proposed:

- **A `Transparent` tag component on the entity.** Lets two entities sharing one material diverge, with no
  error. Also pushes the decision onto whoever authors the scene, where forgetting it silently yields
  opaque glass.
- **An `alpha < 1.0` heuristic on `base_color.a`.** A magic threshold: an import rounding to `0.99` becomes
  blended. Cannot express `MASK` at all, which is the more common case in real content.

The pass split is a CPU-side query, so the mode must be readable without touching GPU state. The bucket is
therefore **derived** — never hand-authored — but not as an entity tag component: `ComponentApplyCallback<T>`
(the scene loader's mesh-apply hook) receives the component to fill, not the entity id, so it has no path to
attach a *second* component to the same entity without an ABI change to `register_component_apply` that
ripples through every existing apply callback. Instead, `alpha_mode` is queried **by material handle**,
mirroring the existing `material_bind_group(core, handle)` lookup: `material_alpha_mode(core, handle)`.
The render core already resolves material handles into CPU-side storage at creation time (`materials[idx]`
in `render_service.zig`, not GPU-only), so this is the same cost and the same "derived, never authored"
guarantee the tag would have given — gbuffer and forward each call it per draw and skip/include accordingly.

#### 8.15.2 Why transparency cannot be deferred, precisely

Not because the G-buffer "doesn't know" what is behind the surface — whatever is behind is opaque, was
encoded, was shaded, and already sits in `hdr`. The reason is narrower: **a G-buffer holds exactly one
surface per pixel.** A transparent fragment and the opaque fragment behind it both land on one pixel, and
there is nowhere to write the second. So the transparent fragment must be shaded at rasterization time and
composited immediately. Forward shades inline by definition; that is not debt.

#### 8.15.3 The forward vocabulary is closed at four hooks

Forward imports hooks, never implementations. Each has a neutral default, so a disabled feature costs
nothing and changes no shader variant (§9.8):

| Hook | Term | Neutral default |
|---|---|---|
| `accumulate_clustered_lights` | direct radiance | empty light list |
| `sample_shadow_visibility` | visibility | fully-lit shadow map |
| `ibl_contribution` | indirect radiance | black environment cube |
| `refraction_contribution` | transmission | opaque — no `hdr` sampling |

These four are the complete **analytic** shading vocabulary: everything computable from the surface and the
lights alone. The distinction that closes the pass:

- **Analytic terms** reach both halves. Replacing the shadow technique, the IBL integration, or the light
  culling changes only the feature behind the hook — forward is untouched.
- **Screen-space terms** (SSAO, SSR, SSGI) sample the G-buffer. A transparent surface is not in the
  G-buffer, so these can never apply to it. This is a property of the topology, not a deficiency of the
  pass. The industry accepts it: Unity's URP denies SSAO to transparents; Unreal exposes translucency
  *Lighting Mode* as an explicit cheap↔full dial.

The mitigation channel is the hook set itself: when opaque gains SSR, transparent gains probe-based
reflection through the **same** `ibl_contribution` hook. The gap is bounded and has somewhere to land.

Forward is reopened only by a genuinely new **term in the rendering equation** — not by a new implementation
of an existing term. Refraction is such a term, and it is the reason transparency gets a fourth hook rather
than three: real glass samples the already-shaded `hdr` behind it, distorted by the surface normal and an
index of refraction. Deferred structurally cannot do this. After refraction we know of no further term:
subsurface scattering is a **material**, and enters through `IMaterial`, not through the pass.

#### 8.15.4 Ordering — sorted blend first, OIT as a module swap

Blending is not commutative, so N overlapping transparent surfaces only composite correctly back-to-front.
Two facts constrain where the ordering lives:

- The ECS **is** the data channel between systems — one system writes a component, the next wave reads it.
  What does not exist is **ordered iteration**: `ke_ecs`'s vtable has no `order_by`, and `query_resolve`
  returns archetype segments in storage order. A per-frame *permutation* also has no per-entity shape.
- Therefore: a system may compute per-entity view depth in parallel (the arithmetic), but the permutation
  is built where the draw list is assembled — inside the pass.

**Sorted per-draw blend is the default path and is not throwaway work.** Weighted-Blended OIT
(McGuire & Bavoil, 2013) is an *approximation*: it weights each layer by a function of depth and washes out
near-opaque surfaces. Production engines ship both, using OIT where sorting is impossible or too costly
(foliage, hair, particles) and sorted blend everywhere else.

Known limit of per-draw sorting, recorded so it is not a future surprise: interpenetrating transparent
meshes, and a concave transparent mesh seen from outside, composite wrongly. Correct ordering there is
per-fragment. That is what OIT buys.

**OIT is a replacement of the transparent module, not a strategy inside it.** The analogy to the light cull
does not hold: a dumb cull and a clustered cull emit the *same shape* (a light list per froxel), so the
shader is indifferent. Sorting and OIT do not — sorting yields a draw order and writes one target; WBOIT
abolishes the order, writes **two** targets (`accum` RGBA16F, `revealage` R8) under **different** blend
states, and adds a fullscreen resolve. The swappable unit is the whole pass, which is exactly the open
composition the chain already supports: both variants read the G-buffer depth and write `hdr`, and nothing
downstream notices.

**ABI prerequisite for OIT.** `ke_gpu_render_pipeline_params` carries a single `blend_state` applied to every
color target — a deliberate simplification taken when MRT landed. WBOIT is the first case that breaks it:
`accum` needs additive (`ONE`/`ONE`), `revealage` needs multiplicative (`ZERO`/`ONE_MINUS_SRC`). OIT
therefore costs per-target blend in the ABI, two resources, and one resolve pass — bounded, but not free.

`KernelEngine.Render.Modern` is a **runtime Module** (`IRuntimeModule` in C#, `ke_runtime_module_params` at the C ABI) — the same shape `KernelEngine.Render.Bgfx` uses today. The V2 renderer doesn't invent a new integration pattern; it slots into the locked one.

### 9.1 What the render module does NOT own

- **Component vocabulary.** `ke_camera_component`, the light components, `ke_mesh_component` are declared in the framework (`src/c/render/include/kernel_engine/render/components.h` + the framework's `ke_world_create` registration). The renderer **reads** these; it does not declare them.
- **Entity lifecycle.** Scene tree owns entities (`RuntimeArchitectureV2.md` §17.1). The renderer queries; it never spawns or destroys.
- **Scheduling.** The runtime owns phase ordering, wave building, dispatch. The renderer declares its systems' phase + access list + thread pinning.
- **A render thread of its own making.** No `std::thread` / Zig thread in the module. The scheduler's enki worker pool is the only source of parallelism (`RuntimeArchitectureV2.md` §8.4, project rule 5). Unlike the bgfx renderer — which pinned every GPU call to a single `ke.render` worker because bgfx demands it — the V2 device records command buffers from many threads, so render passes are **unpinned** and the wave dispatcher parallelizes disjoint passes across the pool (§9.7, pending wgpu-native thread-safety validation).

### 9.2 What the render module DOES own

- **The `ke_gpu_device` instance.** Created at module `on_load`, destroyed at `on_unload` (via the `ke_gpu_device_handle` owner-wrapper). Device + Queue + PipelineCache + the ResourceUploader's staging ring live here. Lifetime = module lifetime.
- **The render passes** declared as runtime systems (there is no render-graph object — §7). Each pass is one `register_system` with `phase = KE_PHASE_UPDATE`/`POST_UPDATE`, `pinned_thread = 0` (unpinned), an `access_list` mixing the components it reads with the render-resource tag-cids it reads/writes, and an `execute` callback that records draws through the render core's pass context (§7.2). The `ke_render_service` service (device + transient pool + barriers + PipelineCache + ResourceUploader staging ring) is created here at `on_load`.
- **PSO compilation, shader hot reload, asset upload kickoff** — all dispatched to the shared `ke_task_scheduler` pool from inside pass execute bodies.

### 9.3 The component-snapshot boundary (R6+)

Locked in `RuntimeArchitectureV2.md` §16:

- Sim systems write `Transform`/`Mesh`/`Camera`/`Light` on the **live** side in `PreUpdate`/`Update`/`PostUpdate`.
- Render systems run in `Update`/`PostUpdate`. The scheduler infers from each render system's `access_list` that its reads route to the **snapshot** side.
- At phase boundaries the scheduler atomically rotates the snapshot index. Sim N+1 writes the new live side while render N reads the new snapshot side. No lock, no copy, no frame-packet object.
- Inference is automatic: any component touched by a render-phase system gets `KE_COMPONENT_DOUBLE_BUFFERED` on registration. Sim-only components stay single-buffered (zero overhead). Escape hatches `[NoDoubleBuffer]` / `[ForceDoubleBuffer]` for the rare exception.
- The L5 helpers don't care which side they read — they consume entity + cid via `ke_system_ctx_get`; snapshot routing happens one layer below in the ecs vtable. A render pass reads `Camera`/`Mesh`/`Light` exactly like any system and gets the snapshot side automatically — it never knows there are two buffers.
- **Two orthogonal id mechanisms — never conflated.** The live/snap split (this section) is the *sim→render data handoff*: it double-buffers ECS component memory so sim N+1 ‖ render N. The render-resource **tag-cids** (§7.1) are *intra-render ordering*: they sequence render passes against each other (forward WRITEs `rg.scene_color`, bloom READs it) and are never double-buffered — no sim system touches them. One answers *when render reads sim data*; the other answers *which render pass runs before which*. Both ride the same `wave_builder`, by different keys, with zero special-casing in the scheduler.

### 9.4 Sim/render pipelining — merge-blocking scope of this branch (done)

**Status (2026-07-12): implemented.** `RuntimeArchitectureV2.md` §16.9 is the as-built record — read it before touching this area again. Short version: the double-buffered-component mechanism §16.3 originally specified turned out to be unbuildable (`ecs_readonly_begin`/`end` is a non-reentrant global flag, incompatible with a sim wave and a render wave ever overlapping on one flecs world). What shipped instead: render-phase queries are extracted once per tick, at the sim→render boundary, into buffers `ke_runtime` itself owns (never flecs entities, never a fixed-schema packet) — so a render-phase system makes zero `ke_ecs` calls, and `tick()` dispatches the render phase as one scheduler task without waiting for it, joining it at the top of the *next* tick before that tick's own extract. `ke_ecs` lost its entire pipelining-aware surface (`concurrent_reads`, the snapshot vtable, `ke_system_ctx_get`/`get_mut`) as a result — it is thread-safe by never being called concurrently, not by a lock.

**frame_packet does not exist in either state.** The LEGACY `*_render_system.cpp` extract-and-write-packet pattern was deleted in C-phase 4 of the runtime arc (`RuntimeArchitectureV2.md` §17.6.1). Render passes read components directly, via `ke_system_ctx_view`, in both the sim-serial and the pipelined state. (The old V2 draft called frame_packet "stable" — retracted, §12.)

**Shutdown crash — root-caused and fixed, not a thread-affinity issue.** A wgpu/Vulkan panic on process shutdown ("Trying to destroy a SurfaceSemaphores that is still in use by a SurfaceTexture") initially reproduced across several examples. The first hypothesis — a present-thread affinity requirement on whichever worker the render coordinator ran on — was wrong and is retracted (see §16.9's corresponding paragraph in `RuntimeArchitectureV2.md`). The actual cause: an example's loop exits and calls `runtime.UnloadModules` (tearing down the GPU device/swapchain) immediately after a tick whose render phase was dispatched but never joined — a plain lifecycle-ordering bug, unrelated to which thread recorded or presented. Fixed by adding `ke_runtime::flush_render` (join any pending render coordinator) and calling it at the top of `RuntimeStartup.UnloadModules`, before any module's `OnUnload` runs.

### 9.5 Hot reload + asset upload threading

- **Shader hot reload**: a filesystem watcher (on a scheduler worker, not its own thread) detects `.slang` changes, kicks Slang compilation on the pool, invalidates affected PSO RAM cache entries. Next frame, the PSO request misses → Mechanism 1.
- **Asset upload**: `ResourceUploader.enqueueUpload(...)` callable from any thread; the staging ring is the sync point; the render-pinned pass issues the GPU copy on the encoder.
- **Background PSO compile**: same pool, same submit pattern; result lands in the cache, next frame's lookup finds it.

### 9.6 What game code touches

- Game code touches `Material`, `Mesh`, `Texture` (managed wrappers around opaque handles, refcounted, sim-safe). `meshNode.MeshHandle = ...` writes `MeshComponent.mesh` in the ecs — a sim-side write picked up next render frame via the snapshot.
- Game code **NEVER** touches `ke_gpu_device`. The device handle stays inside `KernelEngine.Render.Modern`. Even custom user passes declare component access lists and use the L5 helpers, not the device.

### 9.7 Parallel render passes + frames-in-flight (study — not yet locked)

Two **independent** buffering schemes compose; conflating them is the trap.

**Component snapshot (§16 runtime doc) — ECS data only.** Double-buffers `Transform`/`Mesh`/`Camera`/`Light` so sim N+1 writes the live side while render N reads the snapshot side. Runtime-owned; rotates at the phase boundary. It buffers *component memory*, nothing else.

**Frames-in-flight ring — GPU resources.** The backbuffer, the transient render targets, and per-frame uniform buffers are **not** ECS components and are **not** covered by the component snapshot. They are buffered by the render core's own frames-in-flight ring + the swapchain:

- The **backbuffer** is the swapchain's responsibility, not the snapshot's. A begin-frame render-core system acquires the next swapchain image (writes the `rg.backbuffer` tag-cid); the final pass writes it; an end-frame system presents it. The swapchain's own N-buffering + a per-frame fence give the GPU/CPU overlap — the component-snapshot index never touches the backbuffer. So the (N / N+1) split for the backbuffer is just: sim N+1 runs while render N records into and presents frame N's swapchain image; sim never touches the backbuffer, so there is no shared-state hazard to double-buffer at the render-core level.
- **Transient targets + per-frame uniforms** declared via `declare_resource` carry a frames-in-flight multiplier: if the CPU may record frame N+1 while the GPU still executes frame N, each such resource needs `frames_in_flight` physical copies, indexed by a render-core ring counter — **distinct from, and rotating independently of, the component-snapshot index.** The `ResourceUploader` staging ring (§5.3) is one instance of this counter.

**Parallelism within a frame.** Removing the single-thread pin (§9.1) lets the wave dispatcher run disjoint render passes concurrently on the pool. Each pass records into its **own** `ke_gpu_command_encoder` → `ke_gpu_command_buffer`; the render core collects them and submits in wave order (same-wave passes are disjoint, so submit order among them is free). The runtime's same-wave disjointness guarantee makes the render core's per-resource barrier-state tracking lock-free (§7.2).

**Open before locking:**
- wgpu-native thread-safety for parallel command-encoder recording (the WebGPU spec marks `Device`/`Queue` thread-safe; confirm the impl honors it). **Hard gate for unpinning by default.** — Confirmed for *recording*: §16.9 of `RuntimeArchitectureV2.md` documents `WaveBuilder.ClearShadowCull_RealAccessShape_SameWave`, which pins down that `render.clear`/`render.shadow`/`render.cull` already share one wave and have been recording into separate encoders concurrently, on different pool threads, all session, with zero recording-side incidents.
- Whole-phase-on-a-worker (surface acquire/present) thread affinity — investigated and **ruled out** as the cause of the shutdown panic once suspected. Dispatching the entire render phase (§9.4/§16.9) as one task on a load-balanced pool worker is not, by itself, what caused the crash: an isolated reproducer that ticks a few frames and immediately unloads crashed regardless of which worker ran the coordinator, and stopped crashing once the actual bug (an unjoined render task racing `UnloadModules`'s GPU teardown, §9.4) was fixed. No evidence remains of a wgpu-native/Vulkan surface thread-affinity requirement on Windows; the macOS caveat below stands on its own original grounds only.
- `frames_in_flight` depth (2 vs 3) and whether render itself pipelines N+1 CPU recording over N GPU execution, or only sim‖render overlaps. The render-core ring is sized by this choice; the component-snapshot index is unaffected either way.

**Decided (2026-06-22) — remove pinning when bgfx is replaced.** Parallel command *recording* is universal across every target (Vulkan per-thread command pools, D3D12 per-thread allocators, Metal multiple command buffers / `MTLParallelRenderCommandEncoder`, wgpu thread-safe objects, and PS5/Switch/Xbox — multi-thread command building is a core feature of low-level APIs). The only serialization the GPU requires is **per-queue submit/present**, and the wave-builder already provides it: `render.begin_frame` / `clear` / `end_frame` are single systems serialized through the backbuffer tag-cid, so queue ops never run concurrently. bgfx-style pinning exists only because bgfx serializes its *entire* API behind one render thread — an artifact of bgfx's threading model, not a GPU requirement. So `ke_runtime_system_params.pinned_thread` can leave the scheduler in favor of access-list serialization. **One caveat:** keep a narrow "present on the window thread" affinity for **macOS** (`NSWindow`/`CAMetalLayer` mutation requires the main thread); X11/Wayland have lighter constraints. Verify the present-thread requirement per platform when porting; everything else unpins.

**Revisited (2026-07-12) — retracted.** Building the actual §16.9 async `tick()` initially seemed to surface a present-thread-affinity failure on Windows/Vulkan via wgpu-native. Investigation found the real cause was unrelated to thread affinity (§9.4, §16.9) — a lifecycle-ordering bug, fixed without pinning the render coordinator to any particular thread. The "everything else unpins" caveat above stands as originally scoped (macOS only); no evidence of an equivalent Windows/Vulkan requirement remains.

### 9.8 Module decomposition — every feature is opt-in, nothing is baked

**Current deviation (2026-07-02).** The Zig `render_module.zig` is a **monolith**: one `ModuleState` that unconditionally creates the shadow map, the skybox pipeline, IBL sampling, the clustered-forward grid + cull, the tonemap pass, and the forward/forward_lit/magenta pipelines — regardless of whether a given game uses any of them. This was a G3/G5 parity shortcut (get the examples rendering fast), and it violates §2 and §7: *L7 features ship as opt-in passes/modules registered as runtime systems (`KernelEngine.Render.<Feature>` or in the game), the engine does not pick the combination.* It is tracked here as debt, not a design.

**Target.** A game that has no shadows must contain **no** shadow code, shadow shader, or shadow GPU resource — not a disabled branch, not an unused embed. The decomposition:

| Bucket | Passes | Rule |
|---|---|---|
| **Core-mandatory** | forward (opaque draw) + present/swapchain acquire-and-present | Always present; the minimum that puts pixels on screen. |
| **Opt-in feature modules** | shadow, skybox + IBL, clustered-forward + light cull, bloom, tonemap | Each is a separately-composable module the host adds. Absent module ⇒ absent code + shaders + resources. |

The **host decides** the combination at composition time (DI registration); the module ships sane **defaults**; the module — not the render core — owns its config and its GPU resources. The render core and the runtime **configure nothing** because by themselves they *do* nothing — only modules have knobs.

**Two monoliths, distinguished.** The C# module layer is *already* partly decomposed (`ShadowModule`, `SceneRenderModule` are separate `IRuntimeModule`s). The **Zig `render_module.zig` is the monolith that remains** — it still runs every pass regardless of which C# modules were added. Decomposing it (so adding/removing a C# module actually adds/removes the Zig pass + its resources) is the substance of this work; the C# opt-in surface mostly exists.

**Pilot: shadow.** Extract the shadow pass first — it is the only feature that exercises *both* the opt-in decomposition *and* the per-module config surface (§9.9); its config (resolution/frustum/far-plane) is the canonical example. The shadow↔forward coupling is expressed the way §8.12 mandates, not by teaching forward about shadows: the shadow module contributes an `ILightVisibility` impl linked into the shading program, and — together with it — a `rg.shadow_map` tag-cid **read** on the shading pass's access list (shadow_depth WRITES it), so the wave-builder orders shadow-depth before shading with zero special-casing. Forward's *source* stays shadow-agnostic; enabling/disabling the module makes the visibility impl, the `shadow_depth` pass, and the access-list read all appear/disappear together. Skybox/IBL (`IIndirect`), clustered-forward+cull (`ILightIterator`), bloom, tonemap follow the same shape afterward, on demand — not now. *(Retracted 2026-07-05 — see the later status note below: the generic-conformance mechanism this paragraph describes caused an M^N shader-variant explosion; a neutral-default resource, not a linked conformance, is the actual open-composition mechanism.)*

**Deferred (debt) — RESOLVED, see the closing status entry below.** Splitting each module into its own plugin DLL (`KernelEngine.Render.Shadow`) was recorded here as a later step, with a module allowed to live *inside* the same render lib first. That physical split is now done for every pass (tonemap, skybox, ui, gbuffer, shadow, cluster, deferred_lighting, forward) — each is its own Zig-built shared library with its own factory, own shaders, own build files.

**Status (2026-07-03): §8.12's contribution-interface seam shipped for shadow, real-production-wired.** `forward_lit.slang`'s `ke_forward_fs` is generic over `V : ILightVisibility` (declared in `ke.surface`, alongside `IMaterial`); `shadow_feature.slang` is the shadow module's `ShadowMapVisibility` conformance, self-contained (its own pinned resources, not fields reached into the pass). `mat_test_flat.slang` specializes `V = ShadowMapVisibility`, preserving today's shipped behavior exactly (verified: `06_shadow_map` and `03_pbr_directional` unchanged).

**Status (2026-07-05): real opt-in threaded for shadow AND IBL — via four hand-authored shader variants.** `ke_render_feature_params` (`enable_shadows`, `enable_ibl`; NULL = both on, prior behavior) drove whether each feature's GPU resource, pass, access-list dependency, and set-0 bindings existed at all, by making `forward_lit.slang`'s `ke_forward_fs` generic over `V:ILightVisibility`/`I:IIndirect`/`L:ILightIterator` and having each shadow×ibl corner specialize a different combination (`mat_test_flat` / `_no_shadow` / `_no_ibl` / `_no_shadow_no_ibl`). This covered the 2×2, but every further feature would double the pile (dynamic-light opt-in → 8 files) — defeating the point of decomposing the render module: a new feature author would need to know every existing feature to author their combination.

**Status (2026-07-05, later same day): doctrinal reversal — neutral-default resources replace the generic-specialization mechanism above.** The M^N explosion was diagnosed as a consequence of realizing feature hooks via **code linking** (a generic type argument selecting a conformance) instead of **data** (a resource with a neutral default). The fix: `ke_forward_fs` is generic **only** over `T:IMaterial` (materials are the one genericity axis that stays open-ended); shadow visibility, IBL contribution, and dynamic-light accumulation are plain functions (`sample_shadow_visibility`, `ibl_contribution`, `accumulate_clustered_lights` in `shadow_feature.slang`/`ibl_feature.slang`/`cluster_feature.slang`) that forward *always* calls, reading a resource that has a **neutral element** when the producing feature is off: a 1x1 white shadow map (visibility always 1.0), the engine's default black env cube (IBL contribution 0), an empty/zeroed light list (0 accumulated lighting). One shader, one pipeline, for every `enable_shadows`×`enable_ibl` combination — `ke_render_feature_params` now gates only the **expensive** resource (the real shadow-map render target + `render.shadow` pass) and which resource backs the IBL binding (real env cube vs forced-black), never which shader compiles. The four hand-authored variants and their build entries were deleted.

**This retracts the earlier rejection of "a dummy white texture" as a hack (§9.8, pilot paragraph above).** That rejection was itself the mistake: leaving forward permanently ignorant of a feature's *existence* was pursued via generic specialization, which is what produced the M^N pile it was meant to avoid. The neutral-default resource is the actual open-composition mechanism — forward keeps a **fixed, bounded lighting vocabulary** (direct×visibility, dynamic-light accumulation, indirect/IBL, ambient, emissive) and that vocabulary does not grow per optional feature; a genuinely new *kind* of shading term (not one of these hooks) does not get bolted onto forward — it composes as its own additive pass, or waits for the deferred end-state below.

Cluster/light opt-in was not pursued as a fifth axis under the old mechanism (it would have hit the same M^N wall); under the neutral-default mechanism it needs no shader variant either — a scene with no light-culling module would bind an empty/zeroed light-list buffer and get 0 contribution from the same `accumulate_clustered_lights` call. Not yet threaded through `ke_render_feature_params` (today the cluster storage buffers are always allocated); left for a future slice, not blocked on Mechanism 2.

**Mechanism 2 (the build-time PSO-variant generator, §6.2.1) is unaffected by this reversal** — it still applies to the genuinely combinatorial axis, **materials** (`T:IMaterial` × the game's declared feature settings), not to the fixed lighting vocabulary above.

**Deferred boundary, restated.** The deferred+forward hybrid (§8.14) remains where genuinely-new shading-term composition by strangers lives (additive accumulation over a G-buffer) — G-buffer form first when that work starts; a visibility-buffer is a later evolution gated on a bindless **extension with a fallback** (§4.5), never assumed. Neutral-default resources solve the near-term M^N problem for the *fixed* hook set; they do not extend that fixed set.

**Status (2026-07-05, structural pilot): shadow extracted into its own file (`shadow_module.zig`), the monolith-splitting axis this section separately tracks (distinct from the shader-variant axis retracted above).** `render_module.zig`'s `ModuleState` held every shadow GPU resource, its own runtime system, and the light-view-proj math inline; these are now a self-contained `ShadowModule` struct with its own `setup`/`system` functions, taking only borrowed cross-cutting refs (the render core handle, NDC convention, mesh/transform/light/frame cids) as setup parameters rather than reaching into the parent `ModuleState`'s shape. `render_module.zig` holds one `shadow: ShadowModule` field and forwards those refs once, at setup — matching the doc's own "a module may live *inside* the same render lib first" allowance (the plugin-DLL boundary split stays deferred). A shared `cimport.zig` was pulled out for the `@cImport` block: two separate `@cImport`s of the same headers would have produced distinct, incompatible Zig types for the same C struct, breaking any cross-file handle passing. Verified: `06_shadow_map` and `09_many_lights` (`ENABLE_SHADOWS` on and off) unchanged, 275/275 native tests green, no ABI/C# change (this slice is Zig-internal only). Skybox/IBL and clustered-forward+cull remain inline in `render_module.zig`, unextracted — next candidates for the same treatment, not done in this slice.

**Status (2026-07-05, second extraction): skybox pulled into `skybox_module.zig`.** Unlike shadow, skybox has no runtime system of its own — it draws inside the forward pass's own render pass (clear → opaque meshes → skybox, depth LEQUAL, no write), sharing set 0 (`frame_bgl`) with the forward/magenta pipelines. So its module shape is `setup(dev, frame_bgl, out_error)` + `draw(rp, frame_bind_group)` rather than `setup` + a registered `system` callback — the shape a feature module takes follows how it actually composes with the pass graph, it is not a fixed template copied from the shadow pilot. `ModuleState` now holds one `skybox: SkyboxModule` field (pipeline + vbo + ibo) instead of three flat fields; the cube geometry and skybox shaders moved with it. Verified: `05_skybox_ibl` and `13_full_scene` (skybox + shadow + lights combined) unchanged, 275/275 native tests green, no ABI/C# change. IBL's own hook (bindings 7-8, `ibl_feature.slang`) is a forward_lit.slang concern, not skybox's — it stays where it is; skybox only owns the cubemap-background draw. Clustered-forward+cull remains the one inline pass left, and the largest (storage buffers + compute pipeline + a runtime system + forward's per-frame light accumulation all intertwined) — not attempted in this slice.

**Status (2026-07-06, third extraction): clustered-forward + light cull pulled into `cluster_module.zig`.** This was the largest and most interleaved of the three: it owns the grid workload shape (`grid_x/y/z`, `max_lights_per_cluster`, `num_clusters`), six storage buffers (point/spot light data + their per-froxel index/count buffers), the cull compute pipeline, its own "render.cull" runtime system (3 queries: point+transform, spot+transform, camera+transform), and the forward's set-3 read-only bind group. Unlike shadow/skybox, it is not fully self-contained — forward calls `cluster_module.uploadGrid(&st.cluster, bw, bh, near, far)` once per frame (the grid UBO's viewport component is only known from forward's own backbuffer query) and binds `st.cluster.fwd_light_bind_group` directly at set 3 during its draw loop. This seam is the honest shape of the coupling, not hidden behind an extra indirection: forward legitimately needs the light-list bind group to shade, and the cluster module legitimately doesn't know the viewport size on its own. `ModuleState` now holds one `cluster: ClusterModule` field instead of ~20 flat fields; `render_module.zig` resolves the caller's `ke_render_cluster_params` (its own C ABI surface) into `grid_x/y/z/max_lights_per_cluster` locals and hands them to `cluster_module.setup` — the resolved values aren't kept as `ModuleState` fields, since nothing else needs them once the module owns them. Verified: `09_many_lights` at 10,000 point lights and `13_full_scene` (shadow + skybox + clustered lights combined) both render correctly at healthy frame rates, 275/275 native tests green, no ABI/C# change. All three §9.8 decomposition candidates flagged after the neutral-default-resources slice (shadow, skybox+IBL's skybox half, clustered-forward+cull) are now extracted; `render_module.zig` retains only the frame-boundary systems (begin/clear/end), the forward mesh pass itself, and the tonemap/UI passes.

**Status (2026-07-06, fourth extraction): the forward pass itself pulled into `forward_module.zig`, and cross-cutting cid registration lifted into the aggregator.** This closes the "why is forward still in the render module" gap: forward is now a `ForwardModule` with its own state, `setup`, and `system`, holding **borrowed pointers** to the shadow/cluster/skybox modules whose outputs it consumes (shadow map + lvp into set 0's bindings 3-6, the clustered light lists into set 3, the skybox drawn inside its render pass). That is the honest coupling of a forward shading pass expressed as explicit dependencies rather than a parent reaching across one shared `ModuleState` blob — and it is exactly the forward↔cull separation the deferred+forward end-state needs: the cull (`cluster_module`) is its own module producing the light-list resource, forward is the consumer, so a future deferred-lighting pass can consume the *same* cull output without going through forward. `ke_render_module_create` no longer contains any pass logic — it registers the cross-cutting cids once (idempotent-by-name, shared by every module, owned by none), then sets the modules up in dependency order (shadow + cluster → forward → skybox against `forward.frame_bgl`) and registers each pass's system with that module's own pointer as `user_data`. `ModuleState` is now a container of sub-modules (`shadow`/`cluster`/`skybox`/`forward`) + the frame-boundary and tonemap/UI state, holding them only so their addresses stay stable for the borrowed pointers and the systems' `user_data`. Verified: `05_skybox_ibl`, `06_shadow_map`, `09_many_lights` (10,000 lights), and `13_full_scene` (all features combined) each reach their loop and render without crashing; 275/275 native tests green; no C ABI / C# / bindings change (`ke_render_module_create` keeps its signature — the aggregator still exists as the one create entry point). **Not yet done (the next slice) as of this note (2026-07-06) — since shipped, see the 2026-07-08 through 2026-07-10 physical-plugin-split status below:** exposing each pass as its own public factory (`ke_forward_create`, `ke_shadow_create`, …) so a game composes the passes it wants directly instead of through the `ke_render_module_create` aggregator, and the matching C#-per-pass-module split — the aggregator stays as convenience sugar over those factories once they exist.

**Status (2026-07-06, fifth extraction): tonemap pulled into `tonemap_module.zig`, for the same reason as the other four — it is a pass like shadow/skybox/cluster/forward, not core bookkeeping.** `render_module.zig` now retains only what is actually core-mandatory lifecycle rather than an opt-in feature: the frame-boundary systems (`begin_frame`/`clear`/`end_frame`, tied directly to `ke_render_core`'s own `begin_frame`/`end_frame` API) and the UI overlay system (a 3-line forward to `ke_render_core.ui_draw`, which owns the actual pipeline/quad-list). `render_module.zig` is now **283 lines** (down from 983 before this session's five extractions), and is a pure aggregator: it registers the cross-cutting cids once, sets up shadow → cluster → forward → skybox → tonemap in dependency order, and registers each module's system with that module's own pointer as `user_data`. Verified: `13_full_scene` and `09_many_lights` (both exercise tonemap every frame) render without crashing; 275/275 native tests green; no ABI/C# change. This closes the §9.8 decomposition arc started this session — every opt-in-shaped pass (shadow, skybox, cluster+cull, forward, tonemap) is its own file with its own state/setup/system; what remains inline (frame boundary, UI) is core lifecycle, not a feature, and stays. The next slice (per-pass public C factories + a matching C# module split, so a game composes passes directly instead of through the aggregator) is unchanged from the note above — still not started as of this 2026-07-06 note (since shipped, see the 2026-07-08 through 2026-07-10 physical-plugin-split status below).

**Status (2026-07-06, sixth extraction): UI overlay pulled into `ui_module.zig`, for symmetry — it was already stateless (a 3-line forward to `ke_render_core.ui_draw`, which owns the actual pipeline/quad-list), so this is a consistency cut, not a coupling fix.** `render_module.zig` is now **~270 lines**: cross-cutting cid registration, dependency-ordered module setup, and the frame-boundary systems (begin/clear/end — the one piece left inline, because it's `ke_render_core`'s own lifecycle API, not a feature). Every pass in the §9.8 target table (shadow, skybox, cluster+cull, forward, tonemap, UI) is now its own file. Verified: `14_ui_quad` (labels via stb_truetype, the UI overlay's own exercise path) renders without crashing; 275/275 native tests green; no ABI/C# change.

**Status (2026-07-06, seventh extraction): `render_core.zig` itself split — it was a second monolith one layer down, 1189 lines mixing resource declaration, pass-context recording, frame lifecycle, mesh/texture/material upload, and the UI-quad-batch pipeline in one file.** Split by concern, not mechanically by line count: `resource_table.zig` (named-resource declare/import/lookup — the §7 tag mechanism), `pass_recording.zig` (`ke_render_pass_ctx` + the compute-pass recording proxy wgpu-native's render/compute-concurrency restriction requires), `frame_lifecycle.zig` (begin/end_frame + the deferred-upload recorder — the single-threaded choke point the whole parallel-pass design depends on), `asset_upload.zig` (mesh/texture/cubemap/material upload, the load-time asset surface distinct from the per-frame upload path), and `ui_overlay.zig` (the UI quad-batch pipeline). `render_core.zig` itself is now 406 lines: `CoreState`'s definition + its four one-line accessors (`meshAt`/`textureAt`/`materialAt`/`find`, kept in-struct — they're accessors, not logic that belongs elsewhere), the factory/destroy pair, and the vtable wiring. Every split file takes `*CoreState` and operates on it directly (no new indirection, no ownership change) — this is a file-organization cut, not a redesign. Verified: `05_skybox_ibl`, `06_shadow_map`, `09_many_lights`, `13_full_scene`, `14_ui_quad` all render without crashing (covers mesh/material/texture/cubemap upload, the compute-pass proxy via clustered cull, and UI quad batching); 275/275 native tests green; no ABI/C# change.

**Flagged, not resolved, by the split above: the UI-quad-batch pipeline (`ui_overlay.zig`) is a rendering *feature* — its own pipeline, two shaders (`ui.vs`/`ui.fs`), per-frame batching state — exposed as `ke_render_core.ui_quad`/`ui_draw` vtable slots on the "dumb" core itself.** This is the same shape §9.8 diagnosed and fixed on the render_module.zig side (a feature's resources baked into a shared vtable instead of an opt-in module) — just one layer lower, on the core's own public C ABI. Isolating it into its own file does not fix this; the actual fix is an ABI change (drop `ui_quad`/`ui_draw` from `ke_render_core`'s vtable, re-expose UI overlay as its own opt-in pass factory alongside tonemap/forward/shadow) that would move every C# call site (`_core->ui_quad(...)` in `WebgpuRenderModule.cs`). Not attempted without sign-off — recorded here so it isn't rediscovered as a surprise.

**Status (2026-07-06, eighth extraction — the ABI change flagged above, now done): UI overlay moved out of `ke_render_core`'s vtable entirely, into `ui_module.zig` as its own opt-in pass module, matching tonemap/forward/shadow's shape.** `ui_overlay.zig` (the file-split cut) is deleted — its pipeline, shaders, quad-batching state, and draw logic are fully absorbed into `ui_module.zig`, which now owns everything the old `ke_render_core.ui_pipeline`/`ui_bgl_*`/`ui_frame_*`/`ui_vbo`/`ui_vertices`/`ui_batches`/`ui_bind_group_cache` fields held — `CoreState` no longer has any UI-specific fields at all. The ABI surface moved with it: `ke_render_core.ui_quad`/`ui_draw` are deleted from `render_core.h`'s vtable (the "── UI overlay" block); a new `ke_render_module_ui_quad(module, texture, ...)` function is added to `render_module_create.h` — UI is module-owned now, not core machinery, so the call goes through the module, the same way every other module-owned capability does. `WebgpuRenderModule.UiQuad` was updated to call the new binding via `_module.@ref` instead of `_core->ui_quad(...)`; `render.ui`'s runtime system is `ui_module.system`, self-contained (draws through the borrowed `ke_render_core_handle` it holds, same pattern as the other four modules). Bindings regenerated (`scripts/generate_bindings.py`) and the full solution (`dotnet build KernelEngine.slnx`) built clean, confirming no other C# call site referenced the removed vtable slots. Verified: `14_ui_quad` (the feature's own exercise path), `13_full_scene`, `09_many_lights` all render without crashing; 275/275 native tests green. This is a genuine ABI change — `ke_render_core`'s vtable shrank and a new function was added to `ke_render_module`'s — but no other engine surface (native examples, other bindings, other C# projects) referenced the removed slots, so nothing beyond `WebgpuRenderModule.cs` needed updating.

**Debt surfaced by this slice — binding allocation is a manual "well-known ports" scheme, not a real fix.** The C ABI (`ke_gpu_render_pipeline_params.bind_group_layouts`) hard-caps at 4 sets — not a convenience limit, the actual struct field is `[4]`. A dedicated set per feature (the original plan) is therefore not generally available; this slice's shadow resources are pinned instead as *additional bindings appended to set 0* (indices 4-6, chosen by hand and documented only in source comments in `shadow_feature.slang`/`render_module.zig` — no registry enforces the choice). This is structurally identical to manually assigning TCP/IP "well-known ports": it only works because exactly one feature (shadow) claims the extra slots today. **Nothing stops a second independently-written feature from also claiming binding 4** — there is no build-time check, no ownership record, just a comment. Investigated and rejected as insufficient for automating this: `slangc -reflection-json`'s flat parameter/entry-point dump does not resolve nested resource fields inside a generic-instantiated `uniform` parameter (a feature-owned resource struct reports as an opaque `struct` with no binding info) — so reflection cannot mechanically derive "which binding did the shadow feature's texture land on" the way it can for plainly-declared globals. Two real fixes exist, both deliberately not pursued in this slice:
- **§6 Mechanism 2 (the build-time manifest)** — the doctrinal answer: bindings become a build output derived from which features are actually composed into a given specialization, never hand-assigned. This is the fix that scales to N independently-developed features without a coordination meeting.
- **Bindless** (see below) — sidesteps enumerated slots entirely via a descriptor array + dynamic index, so there is no "slot 4 vs slot 7" question to coordinate at all.

Until one of those lands, treat "who owns which appended binding in set 0" as a manually-coordinated resource — same discipline as editing `/etc/services` by hand.

**Bindless investigated and scoped out of the core composition mechanism.** wgpu-native (our L3 backend) does support descriptor-indexing-style binding arrays (`TEXTURE_BINDING_ARRAY`/`BUFFER_BINDING_ARRAY`/non-uniform-indexing) via its **native-only** feature set — not part of portable core WebGPU, and WGSL's *standard* grammar has no unbounded/runtime-sized binding-array syntax at all; wgpu's version is its own extension to WGSL. This is exactly the shape §4.5 already legislates for: *"if WebGPU hasn't shipped it, it goes in an extension"* — bindless belongs behind `ke_gpu_bindless` (declared, not yet implemented), never promoted into the portable `ke_gpu_device` core, because doing so would sever any future real-browser-WebGPU target. **Decided:** the feature↔pass composition seam itself (§8.12) — the mechanism this whole section is about — must stay on the portable common denominator; it cannot be built to depend on an extension that is absent on an entire class of target. So bindless is not the fix for the binding-allocation debt above at the *architecture* level. It remains legitimately available to an individual pass/feature that wants to reach for it directly through the extension mechanism (§4.5) on backends that support it — that choice is the pass author's to make, same as any other extension use — but the core seam does not and will not assume it exists. Whether `slangc`'s WGSL backend can even target wgpu's binding-array syntax is unverified (a future spike, not blocking).

**Status (2026-07-08 through 2026-07-10, physical-plugin split): every pass extracted into its own physical Zig library, closing the "Deferred (debt)" item above.** Following an explicit PO request ("separar fisicamente os modulos, cada um com seus shaders e seu create, cada um uma lib" — "the modules must not know each other"), each of the eight in-process modules the earlier statuses built (tonemap, skybox, ui, gbuffer, shadow, cluster, deferred_lighting, forward) was pulled out of `ke_render_core`'s single Zig library into its own directory under `src/zig/render/<pass>/`, each with:

- its own C ABI factory header (`ke_render_<pass>_create.h`) and exported `ke_render_<pass>_create(...)` — the one symbol the rest of the engine calls;
- its own `.slang` shader(s) and its own `build.zig` / `build.zig.zon` / `CMakeLists.txt`, compiling to a genuinely separate shared library (`ke_render_<pass>.dll`/`.so`), not just a separate source file inside `ke_render_core`'s;
- no direct struct-pointer access to any other pass. The two previously-coupled passes (deferred-lighting and forward, which used to take `*ShadowModule`/`*ClusterModule` directly) were decoupled first by extending the named-resource table (`resource_table.zig`) to publish **buffers and bind-groups** by name (not just textures/views, which it already supported) — shadow publishes `"shadow_map"`/`"shadow_lvp"`, cluster publishes `"cluster_lights"`/`"light_clusters"`, and deferred/forward resolve them by name, exactly the way `tonemap_module.zig` already resolved `"hdr"` by name. An absent resource (feature disabled) resolves to `KE_GPU_INVALID_HANDLE`/neutral default rather than requiring a separate "enabled" flag to cross the module boundary.

Shader files imported by more than one physical plugin (`forward_common.slang`, `gbuffer_encoding.slang`, `shadow_feature.slang`, `ibl_feature.slang`, `cluster_feature.slang`) moved to the shared `src/shaders/` tree, sibling to `ke.slang` — the shader-side equivalent of a public kernel header. `refraction_feature.slang` stayed private to the forward plugin (only pass that calls it).

`render_module.zig` — once the 1189-line monolith diagnosed at the top of this section — is now a **thin composition-root aggregator**: it registers cross-cutting cids once, resolves each `ke_render_cluster_params`/`ke_render_feature_params` default, then calls each pass's `ke_render_<pass>_create(...)` in dependency order (shadow → cluster → gbuffer → deferred_lighting → skybox → forward → tonemap → ui), holding only the borrowed opaque handle each factory returns. Registration **order** still matters — the runtime's wave-builder places a system based on the graph known at registration time (an online/incremental scheduler), not a full rebuild each tick — so each combined create() call had to land in the exact relative position its old separate `registerSys` call used to occupy; getting this wrong (tonemap, initially) produced a real crash reading uninitialized per-slot encoder memory before `begin_frame` had run. `begin_frame`/`clear` are now registered first, unconditionally, ahead of every pass's setup, which resolved the only case (gbuffer/shadow) where "setup must precede a downstream pass's setup" and "register must follow begin_frame" pulled in opposite directions.

Verified per extraction: full clean rebuild (`cmake --build --preset win`), 279/279 ctest, `dotnet build` 0 errors, dotnet test suite green, and visual confirmation via `dotnet run` (never `--no-build`) on `05_skybox_ibl`/`06_shadow_map`/`09_many_lights`/`13_full_scene`/`19_transparency`/`14_ui_quad` covering every pass's own exercise path. Landed as one commit per pass. **This closes the module-decomposition arc §9.8 opened.** What remains open, not closed by this work: the binding-allocation "well-known ports" debt and the build-time PSO manifest (§6 Mechanism 2) below — physical separation did not touch either.

### 9.9 Per-module configuration — a **native** `ke_configuration` contract

Configuration is a **renderer prerequisite** (a module cannot own its knobs without it) but it is a **cross-cutting engine capability**, and this is a **multi-language engine — C# is not special.** Settings are far too important to be C#-exclusive. Therefore configuration is a **C-ABI contract**, exactly like `ke_ecs` / `ke_allocator` / `ke_resource_cache`; the C# side is a thin wrapper, and Lua/Rust/future hosts consume the same vtable.

**Status: shipped.** `ke_configuration` (`src/c/configuration/include/`, Zig impl at `src/zig/configuration/`) is the native kernel primitive this section specifies — typed getters + `subscribe`, format-agnostic — with a TOML loader plugin (`src/zig/configuration/toml/`) populating it and `KernelEngine.Configuration` (`src/csharp/configuration/`) as the thin C# wrapper. The "current deviation" this note originally flagged (pure-C# `IProjectConfig`/`TomlOptionsBinder`) has been retargeted onto the native contract, per the decision below. Not yet threaded through as any render pass's actual per-module config source (the hardcoded consts — `SHADOW_RES`, `GRID_X/Y/Z`, `MAX_LIGHTS_PER_CLUSTER` — still default in `ke_render_cluster_params`/pass factory signatures rather than reading `ke_configuration` sections); that wiring is unstarted, tracked in the debts list below.

**The contract (decided 2026-07-02).**

- **`ke_configuration` is a kernel primitive, format-agnostic** — a typed section/key store + a **change subscription** (`subscribe(section, callback_fn, user_ctx) → subscription`; the native equivalent of `IOptionsMonitor.OnChange`). It mirrors `ke_resource_cache`: a generic kernel built-in that knows nothing about file formats.
- **TOML parsing lives in a loader plugin, not the kernel** — the framework plugin already vendors **tomlc99**; a loader reads `Project.toml` and populates `ke_configuration`. Same pattern as "an asset loader populates `ke_resource_cache`". The kernel never sees TOML.
- **Typed access = typed getters (decided): `get_uint` / `get_float` / `get_string` / `get_bool` / arrays**, each taking a default. A module reads its section at init and stores the values. *(Debt / alternative — see below.)*
- **C# `KernelEngine.Configuration` becomes a thin wrapper** — a custom `IOptionsMonitor<T>` backed by `ke_configuration`, so C# game devs keep the idiomatic `IOptionsMonitor<ShadowOptions>` while the capability is native. Precedent: `Allocator` wraps `ke_allocator*`.

**Rules.**

1. **Opt-in is DI/module registration, never TOML-section presence.** Adding the module in code (`AddShadowModule()` / `new ShadowModule()`) is what makes the feature exist; the `[shadow]` section only *tunes* an already-composed module. A stray TOML section must never conjure a feature — otherwise the "no shadow code in a game without shadows" guarantee (§9.8) is lost.
2. **Runtime change is applied at the owning system's own execution point — no pinning.** The `subscribe` callback **latches** a pending value; the module applies it (e.g. destroy+recreate the shadow map at the new resolution) at the top of its *own* render system's next run, where the wave-builder already grants exclusive access to the resource tag-cid (§7.2, §9.7). The callback fires from an arbitrary thread (a settings menu, later a file watcher) and must **never** touch GPU resources directly, and must **never** reach for `DispatchPinned` — reintroducing a pin here would contradict §9.7's "remove pinning" direction. Latch-then-apply is the whole mechanism.
3. **Defaults live on the module** (the params struct / POCO), applied when the section or a key is absent. `ke_configuration` holds no default catalog.

**Debts / deferred, recorded so they are not rediscovered as regressions:**

- **Descriptor-based binding** — a field-descriptor table (offset + type + key) per options struct + a single `bind(section, descriptor, out_struct)`, i.e. the native analogue of `TomlOptionsBinder`'s reflection. **Possibly cleaner and more ergonomic than typed getters**; deliberately *not* chosen for the first cut (more machinery to prove the contract). Revisit as sugar once the getter path is proven — it may well be the better long-term surface.
- **File-driven reload-on-save** (edit `Project.toml` → change fires) belongs to a **future hot-reload arc** — noted, not built. The near-term change path is **programmatic** (a settings API calling the config), which is the more common real use case anyway. Aligns with chapter 16 §5's "Hot reload" open question.
- **Hardcoded consts migrate to module config** — `SHADOW_RES`, `GRID_X/Y/Z`, `MAX_LIGHTS_PER_CLUSTER` are exactly the "module decides for the user" values this system replaces. Each pass is now its own physical plugin with its own factory params (§9.8), which is where these defaults currently live (`DEFAULT_GRID_X` etc. in `render_module.zig`'s aggregator, resolved from the caller's `ke_render_cluster_params` before being handed to `ke_render_cluster_create`) — moving them onto `ke_configuration` sections instead of caller-supplied params structs is still unstarted.
- **Native DI container is a separate, later arc.** The same multi-language logic that makes config native applies to dependency injection — today DI is `Microsoft.Extensions.DependencyInjection` in C# (composition root) with native plugins receiving deps via factory params ("manual DI"). A native IoC container (codegen-based, or a typed service registry keyed by interface-id — more refined than a raw service locator) is desirable but out of scope here. **Short-term stance:** MS.DI stays the C# composition root; native modules get deps by params. Config does **not** block on DI.

---

## 10. Migration plan — parallel build, Zig greenfield alongside CMake

V2 is a **new Zig lib built beside** the shipping bgfx renderer, not an in-place rewrite. The old renderer keeps shipping; V2 is a separate DI slot. Because V2 is greenfield, it is a natural early instance of incremental Zig adoption (`ZigMigrationPlan.md`): its own `build.zig` produces the V2 DLL and links the webgpu distribution, **coexisting** with the CMake tree that builds everything else. No full build-system swap is a prerequisite.

### Phase G0 — This doc + headers re-homed (done)
Doc carried onto `feat/render-v2-zig`; Slang shaders + L3 C ABI headers ported and reshaped to current conventions (§4.0). C++ impl discarded.

### Phase G1 — Slang spike + webgpu triangle (1-2 sessions)
- `slangc` in the toolchain; `compile_shaders.py` `.slang` path → SPIR-V.
- The render-v2 `build.zig` links `eliemichel/WebGPU-distribution`; a Zig `ke_gpu_device_webgpu` fills enough of the L3 vtable to clear + present.
- Render a triangle from a `.slang`-compiled module through the full L3 surface. No engine integration. **Hard gate: triangle renders.**

### Phase G2 — L4/L5 render core (Zig impl behind C ABI) (3-5 sessions)
- `gpu_commands.h` L4 typed objects (`CommandEncoder`/`RenderPass`/`ComputePass`) filled by the Zig device.
- The **render core** (`ke_render_service` service + `ke_render_pass_ctx`, C ABI) with its Zig impl: resource registry (tag-cid minting), transient pool, barrier tracking, and the `RenderPassBuilder`/`MaterialBinding`/`PipelineCache`/`ResourceUploader` helpers reached through the pass context (§5, §7).
- A throwaway pass registered as a runtime system proves the `register_system` → `begin_pass` → record → submit path end to end. No render-graph object.

### Phase G3 — Runtime module + first engine scene (2-3 sessions)
- `KernelEngine.Render.Modern` runtime module: device + render core at `on_load`; each pass registered as an **unpinned** runtime system with an access list mixing component reads and render-resource tag-cids; reads components via `ke_system_ctx`.
- `example_01` opts into Modern via DI; both renderers selectable. **Hard gate: example_01 visually matches Bgfx.**

### Phase G3.5 — Runtime snapshot pipelining (runtime §16) — MERGE-BLOCKING — DONE
**Status: shipped, gate satisfied.** The as-built mechanism diverged from the plan below (which assumed a `ke_ecs` double-buffer that turned out unbuildable — flecs readonly mode is non-reentrant); `RuntimeArchitectureV2.md` §16.9 records what actually shipped (runtime-owned extract + async `tick()`), and the shutdown crash that was the last open issue is fixed (§9.4). The original plan text is kept below as the design log.

With a multi-pass scene now running (G3), implement the deferred `RuntimeArchitectureV2.md` §16 component snapshot — this branch's shared deliverable with render v2, not a later option (§9.4): `ke_ecs` double-buffer contract (`component_register_v3` + `KE_COMPONENT_DOUBLE_BUFFERED` + `swap_snapshots`), flecs `X_live`/`X_snap` impl + phase-aware routing, startup inference over render-system access lists, scheduler swap at the phase boundary. Render code is untouched (reads via `ke_system_ctx`). **Hard gate: sim N+1 ‖ render N pipelines; the branch does not merge to main without it.**

### Phase G4 — PSO Mechanism 1 (ubershader + magenta) (3-4 sessions)
`PipelineCache` (RAM only); build-time ubershader (PBR forward + shadow + depth prepass); magenta placeholder; background compile via the worker pool; hot reload invalidates RAM entries. **Goal: dev iteration never stalls.**

**Status (2026-07-02): partial, and deliberately not the load-bearing path.** Magenta placeholder + the has-material/no-material PSO selector are wired in `render_module.zig`'s `forwardSys`/`forwardSetup` (see §8.10 status note for the IMaterial half). No ubershader, no `PipelineCache`, no background compile, no runtime PSO-miss detection — every mesh with a material draws through the single `forward_lit` pipeline built at engine-build time; magenta today only fires for the hardcoded "no material assigned" case, not a real cache-miss path.

**Status (2026-07-13, superseding the note above): Mechanism 1's dedup+never-stall half shipped for real** — see §6 Mechanism 1's own 2026-07-13 status note above; `PipelineCache` (RAM-only `std.AutoHashMap`), magenta fallback, and async background compile are all live and exercised by every pass. The ubershader half of Mechanism 1 is still not built (every miss falls back to magenta regardless of ubershader-compatibility).

**This is not yet the anti-stutter system.** The doctrine's actual answer to the Godot problem (§6 intro) is **Mechanism 2** — the build-time manifest that makes the full PSO set statically derivable, so nothing compiles during gameplay. Mechanism 2 is **0% built**: no `ke build manifest` CLI, no cartesian-product walk, no `psos.manifest`, no per-machine disk cache (Mechanism 3) to serve it from. Mechanism 1 exists only as the *safety net* for cases the manifest legitimately can't predict ahead of time (modder content, dev-iteration staleness) — it is never meant to be the primary path in a shipped game. Sequencing per §6.6 remains: Mechanism 1 → Mechanism 3 → Mechanism 2, with Mechanism 2 required before shipping any release game. **PO direction (2026-07-12): neither the ubershader nor Mechanism 2 is currently prioritized** — paused here deliberately, not stalled.

### Phase G4.1 — PSO Mechanism 3 (disk cache + driver hash) (2 sessions)
`driver_hash` at boot; cache dir per (game, engine_ver, driver); lazy load → create_pipeline_from_blob; write on compile success; invalidate on hash change.

### Phase G4.2 — PSO Mechanism 2 (build-time manifest) (3-4 sessions)
`ke build manifest` CLI verb; walk materials; cartesian product → `psos.manifest`; first-launch compile pass; coverage metric vs examples.

### Phase G5 — Slang + feature parity, example-by-example (locked plan, 2026-06-22)

Slang is built **incrementally** — do NOT stand up §6 (PSO three-mechanism) or the full §8 (`IMaterial` templates) before the first lit mesh draws. The order:

**G5.0 — minimal Slang path.** `slangc` in the toolchain; `compile_shaders.py` gains a `.slang` → SPIR-V path (§8.2); a direct "compile shader module → create pipeline" path — no ubershader / manifest / disk cache yet.

**G5.1 — forward mesh pass.** A render pass that reads `Mesh`/`Transform`/`Camera` from components and draws a lit mesh with a Slang material. Convert `examples/csharp/01` first (the first 3D scene) — this proves Slang + forward + component reads through the render core.

**G5.2+ — feature-by-feature, converting `examples/csharp` one at a time, in order.** Each conversion pulls a new pass/material capability; the bgfx equivalent is deleted at parity (Bgfx stays selectable via DI until then, §12):

| Example | Capability the conversion adds |
|---|---|
| 01 basic scene      | forward mesh + minimal material (G5.1) |
| 02 textured quad    | texture sampling in materials |
| 03 pbr directional  | PBR GGX + directional light |
| 04 normal map       | tangent-space normal mapping |
| 05 skybox / IBL     | cubemap skybox + image-based lighting |
| 06 shadow map       | shadow-caster pass + directional shadow |
| 07 / 08 / 09 lights | point/spot, then clustered forward + light culling for many lights |
| 10 hdr bloom        | HDR target + bloom chain — **first cross-pass *sampling*** → needs render-core barriers (the §9.4 follow-up) |
| 11 ssao             | Hi-Z + SSAO pass |
| 12 / 13 assets+scene| asset-driven materials end to end |

§6 (ubershader → build-time manifest → per-machine disk cache) and §8 (the template authoring surface) layer in **after** the direct path proves out — §6 before any non-trivial game ships, §8 as the authoring surface matures. The first concrete step is G5.0: verify `slangc` availability, compile a test `.slang` to SPIR-V, create a pipeline with it.

### Phase G6 — Cut over default; deprecate Bgfx
Default DI swap. Bgfx becomes "legacy stable" (critical fixes only). Delete after 3+ months of Modern as default with no regressions.

### Phase G7 — Modularity + native configuration (renderer modularity; **prerequisite for "done")**
**Done: module decomposition.** `render_module.zig`'s in-process split (shadow → skybox → cluster+cull → forward → tonemap → UI → the `render_core.zig` file split) and the subsequent physical-plugin split (§9.8's closing status — every pass is now its own Zig library with its own factory/shaders/build) together complete the "core-mandatory vs opt-in feature module" decomposition this phase targeted.
**Done: native configuration contract.** `ke_configuration` (§9.9) shipped as a kernel primitive + TOML loader + thin C# wrapper.
**Not done: wiring per-pass config through `ke_configuration`.** Each pass plugin still takes its tunables (`grid_x`/`max_lights_per_cluster`/shadow resolution/etc.) as caller-supplied factory params with hardcoded engine defaults, not as `ke_configuration` section reads with runtime `subscribe`-driven reconfiguration (§9.9's "latch-then-apply, no pinning" mechanism). This is the remaining slice before G7 can close. Native DI container remains explicitly **not** in scope (§9.9 debt).

### Risk gates
- G1: webgpu triangle renders. **Hard gate.**
- G3: example_01 visually matches Bgfx. **Hard gate.**
- Slang fails at G1 → fall back to bgfx `.sc` for engine shaders + Slang for user material shaders only (smaller win).

---

## 11. Culling architecture — render-graph passes, not a dedicated pipeline

Culling is **not** a hardcoded pipeline stage. It's a **set of optional render-graph passes** that consume the entity columns and produce filtered lists for downstream draws. The game composes the chain that fits its scene; the engine ships the two basic flavors.

### 11.1 The flow

```
SIM PHASES (no special "extract" — there is none):
    write Transform, Mesh, Material, AABB, lod_group_id, layer_mask as game state.

RENDER PHASE (pinned to ke.render, reads via snapshot post-R6):
    ┌─ FrustumCullPass        (engine built-in)
    │      access: Transform READ, MeshAabb READ, Camera READ; VisibleSet WRITE
    │      first impl: CPU SIMD over the snapshot Transform+AABB columns (~5-10 ns/entity)
    │      G5+ impl: compute-shader variant for huge scenes
    ├─ OcclusionCullPass      (engine built-in — Hi-Z based)
    │      access: VisibleSet RW, Hi-Z texture (prev-frame depth); compute, ~50 µs / 100K entities
    ├─ [USER PASSES — opt-in]  PortalCullPass, RoomCullPass, custom LOD selector …
    └─ DrawPass(es)           (consume final VisibleSet + read Mesh/Material via snapshot)
```

No "publish all entities to a frame packet" step — there is no frame packet. Cull passes read components straight from the ecs snapshot (post-R6) or live storage (pre-R6). The "full entity list" is a column iteration, not a copied list.

### 11.2 Why this matters

1. **Composable** — simple game registers only `FrustumCullPass`; open-world adds `OcclusionCullPass`; a level game with PVS/portals adds its own pass between built-ins and Draw. The engine doesn't pick the combination.
2. **Hi-Z is shared infrastructure** — the depth pyramid `OcclusionCullPass` consumes is the same one TAA/SSAO/SSR consume. Built once, cached; a graph dependency, not a special case.
3. **GPU-driven culling is the same architecture, bigger** — when GPU instancing lands, `OcclusionCullPass` writes an indirect draw buffer instead of a CPU list. Same node, different output kind.
4. **Mods/users extend without forking** — a game-specific cull strategy ships as another plugin's render-graph pass.

### 11.3 / 11.4 What the engine ships (and doesn't)

Ships: **`FrustumCullPass`** (AABB-vs-6-planes, CPU SIMD first, ~50-100 LoC; compute variant in G5+) and **`OcclusionCullPass`** (Hi-Z + AABB reprojection, ~300 LoC + one compute shader; wrap Frostbite / Ubisoft Anvil patterns). Does NOT ship: portal culling, PVS, antiportals, voxel occlusion, scene-graph cell culling — game-specific, plug your own. Per-light culling is already clustered forward shading's job, a different concern.

### 11.5 Current clustered-forward is a stress-test baseline, not the final tuning

Confirmed via the `09_many_lights` classic-vs-clustered comparison (2026-07-04): clustered forward's per-froxel cull correctly bounds *shading* cost to lights actually near the camera (a light whose sphere never overlaps a froxel AABB never reaches the fragment shader — frustum culling of lights falls out of the froxel binning for free). But two things are not yet refined:

- **The cull compute itself is brute-force**, O(clusters × total scene lights), no broad-phase/spatial pre-filter — a light far outside the frustum is still tested against every froxel before failing. Fine at today's scales; would need a spatial pre-pass if the scene ever has orders-of-magnitude more lights than are ever visible at once.
- **The forward pass has no depth prepass or front-to-back draw sort** — same-pass depth test/write means overdraw can still fully shade (material + light loop) a fragment that a nearer surface later overwrites. Not a per-light problem, but it does mean shading cost isn't purely "scene complexity + light cost," it's scene overdraw × light cost in the worst case.

Neither is a regression — they're just not solved yet. Noting so this doesn't read as a finished forward++ when it's a working baseline.

---

## 12. What V2 explicitly does NOT change (non-goals)

- **`ke_render` vtable** stays mostly as-is at L7 for the imperative `submit_mesh`/`submit_skybox` slots game code calls (legacy entry points). Modern implements the same vtable so the swap is transparent. The modern preferred path is "set the component, let the passes pick it up" — `submit_mesh` becomes an escape hatch.
- **`Material` / `Mesh` / `Texture` C# wrappers** stay. Refcounting, handle types preserved.
- **Render graph contract** — already shipped, used as-is.
- ~~Frame packet contract — stable.~~ → **Retracted.** The runtime work (`RuntimeArchitectureV2.md` §16, §17.6.1) replaced it with per-component snapshot before this doc reached "Accepted". Modern never reads or writes a frame packet; it reads components via `ke_system_ctx`.
- **bgfx renderer** stays alive until full V2 parity. Not a line touched during G1-G4.
- **Component vocabulary** — Modern does NOT redeclare `Camera`/`Light`/`Mesh`. It reads the framework's `components.h`, exactly like Bgfx does. A different framework can declare a different vocabulary; Modern reads whatever the registered framework ships.

---

## 13. Open questions (lock during the relevant phase)

1. **Direct Vulkan/D3D12 backend** as a second `ke_gpu_device` impl after webgpu-native. Decided for now: webgpu-native first (§4.6). Revisit if a capability is missing or the Rust-runtime dependency becomes unacceptable. The §2 layering makes the second backend additive.
2. **Zig source layout for L2/L4/L5 — DECIDED.** `src/zig/render/` parallel to `src/c` / `src/cpp`: `src/zig/render/webgpu/` (L2 backend, shipped) + `src/zig/render/core/` (L5 render core, to land), with the C ABI headers in `src/c/render/include/`. Backend done; core directory lands with the L5 headers.
3. **L4/L5/L6 surface — LOCKED (was deferred).** L4 (`gpu_commands.h`) and L5 (the render core: `ke_render_service` service + `ke_render_pass_ctx`) are **C ABI** so any module — C, Zig, or C# — authors render passes; the Zig helpers are the implementation behind that contract (Option A). The L6 render-graph object is **eliminated**: a pass is a plain runtime system, ordering is the runtime's wave-builder, and render resources are zero-size tag-component cids in the access list (§7). The double recording surface (§4.0.5) and inline forwarders (§4.0.1) stay collapsed.
4. **Disk PSO cache location** — per-user (`%LOCALAPPDATA%`) keyed by project + engine version. Lock during G4.1.
5. **GPU handle type safety** — bare `uint64_t` (WebGPU style) vs struct-wrapped `{ uint64_t id; }` (engine `handles.h` style). Lock during G1.
6. **Bindless** — WebGPU is conservative; Vulkan/D3D12 allow effectively-bindless descriptor sets. Exposed via the `ke_gpu_bindless` extension (§4.5). Lock the extension API shape when the first GPU-driven pass needs it.
7. **Slang language version pinning** — pin a Slang version in the toolchain, bump deliberately. Document alongside the Zig version pin.
8. **Render-pass parallelization + wgpu-native thread-safety (study, §9.7).** Removing the single-thread `ke.render` pin lets the wave dispatcher parallelize disjoint passes (each records its own command buffer; the render core submits in wave order). Gated on confirming wgpu-native records command encoders safely across threads. Lock before unpinning by default.
9. **Frames-in-flight depth (study, §9.7).** How many physical copies of the backbuffer / transient targets / per-frame uniforms the render core rings, and whether render pipelines N+1-record over N-execute or only sim‖render overlaps. Independent of the component-snapshot index. Lock during the first multi-frame G3+ bring-up.

---

## 14. Alternatives considered

- **Keep bgfx, refactor in place** — rejected. bgfx's high-level API hides the control we need; staying means continuing to lie that the engine uses Vulkan when it uses OpenGL-shaped Vulkan. Refactoring in place fights every example simultaneously.
- **wgpu-native (Rust) vs direct Vulkan as the first backend** — wgpu-native chosen. It covers PC (Vulkan/D3D12/Metal) + mobile + web from one ABI, ships pre-built, and *was the design source for the L3 ABI* so the wrapper is near-mechanical. Direct Vulkan stays available as a second backend the layered architecture admits without disturbing L4+.
- **The Forge** — retired. With Modern V2 + webgpu-native covering the platform matrix (RT pipelines the only gap, not needed until M5+), importing someone else's render abstraction (Apache 2.0 attribution, larger binary, opinionated state model) costs more than it saves. When the engine outgrows wgpu, the §2 layering lets us write our **own** second backend in-house.
- **Implement L3 in C/C++ instead of Zig** — rejected. The engine is adopting Zig incrementally for impl behind the C ABI (`ZigMigrationPlan.md`); a greenfield lib is the lowest-risk place to start, and Zig's `@cImport` consumes `webgpu.h` and the kernel headers directly with no FFI ceremony. The ABI stays C either way.
- **Sokol** — too constrained, no compute on legacy backends, no RT path. Rejected.

---

## 15. Implementation language & build — Zig, coexisting with CMake

The engine is **not** doing a big-bang Zig migration. Per `ZigMigrationPlan.md` (deferred as a wholesale effort), Zig is adopted **incrementally, lib by lib, as each is implemented or refactored**, and `zig build` **coexists** with CMake throughout.

Render V2 is the first **greenfield** instance of that policy — there is no existing C/C++ impl to migrate, so it starts in Zig directly with no regression risk to existing code:

- **The C ABI stays C.** L3 (`ke_gpu_device` + enums + commands), the extension headers, and the factory `_create.h` are `extern "C"` headers under `src/c/render/include/`. C# binds them through the generator; a future C/C++ backend or consumer uses them unchanged.
- **Zig is the impl language** behind that ABI for L2 (webgpu backend), L4, and L5. Zig `@cImport`s `webgpu.h` (backend) and the kernel headers (vtable types, `ke_error`), filling the C vtables via `export fn ... callconv(.C)`. The error model is `ke_error` exactly as in C — `ZigMigrationPlan.md` §6 (native Zig errors inside, `ke_error_set` + `@src()` at the seam; `errdefer` replaces the `goto fail` ladder).
- **The build.** The render-v2 lib has its own `build.zig` that produces the V2 DLL and links the webgpu distribution. It coexists with the CMake build of every other module — the load-bearing contract is only the DLL base name + the exported `ke_*_create` symbol (`ZigMigrationPlan.md` §7), so the C# native-dep copy is agnostic to which tool produced the DLL. The webgpu distribution's prebuilt ABI is a linking constraint tracked jointly with the Zig plan (§4.6).
- **No private threads** (project rule 5) and **no `assert`/`abort`** (project rule 6) in the Zig impl, same as the C plugins — failures translate to `ke_error`.

---

## 16. What was carried from `feat/render-v2`, and what was discarded

The previous branch (`feat/render-v2`) was authored before the kernel include reorg, the `bool`+`ke_error**` ABI idiom, and the handle-ownership refactor, and targeted a C++ implementation. The audit:

| Artifact | Disposition | Rationale |
|---|---|---|
| This design doc (incl. §4.5 extension model, §8 shader authoring) | **Carried + reshaped** | The only material not already on `main`; the high-value output of the branch. |
| Slang shaders (`src/shaders/ke/*`, `materials/test_flat`) | **Carried verbatim** | Language-agnostic; relogic on first impl, structure kept. |
| L3 C ABI headers (`gpu_device.h`, `gpu_enums.h`, `gpu_commands.h`) | **Carried + reshaped** | Enums/params structs are a sound starting point; reshaped to §4.0 conventions and relocated to the render domain. |
| `static inline` forwarders (~200 lines across the headers) | **Discarded** | "C ergonomics" privilege — violates "no privileged caller language"; obsolete under Zig (§4.0.1). |
| Device-side flat `rp_*`/`cp_*`/`encoder_*` primitives | **Discarded** | Redundant second recording surface; the typed L4 objects carry recording directly (§4.0.5). |
| C++ impl (`backend_webgpu` ~1160 ln, core L5 ~1500 ln) | **Discarded** | Reimplemented in Zig; was never going to live under `src/cpp`. Logic consulted as reference, not ported blind. |

---

## 17. Status & next actions

- [x] Design carried onto `feat/render-v2-zig` from current `main`; conventions reconciled (§4.0); §9/§11/§12 already aligned with the runtime contracts on `main`.
- [x] Slang shaders + L3 C ABI headers ported and reshaped.
- [x] Lock the structural §13 questions: Zig source layout (§13.2) and the L4/L5/L6 surface (§13.3) — **decided**: render core is C ABI (Option A), the render-graph object is eliminated, passes are runtime systems ordered by access-list, resources are tag-component cids (§7).
- [x] **Module decomposition (§9.8), including the physical-plugin split.** Every render pass (tonemap, skybox, ui, gbuffer, shadow, cluster, deferred_lighting, forward) is its own Zig-built shared library with its own factory/shaders/build files; `render_module.zig` is a thin composition-root aggregator. Native `ke_configuration` (§9.9) also shipped. Remaining: wire each pass's tunables through `ke_configuration` instead of hardcoded factory-param defaults (Phase G7).
- [x] Validate wgpu-native thread-safety (§13.8) for parallel command recording — confirmed (§9.7). The shutdown crash once suspected to be a surface acquire/present thread-affinity issue was root-caused as an unjoined-render-task lifecycle bug instead (§9.4/§9.7, `RuntimeArchitectureV2.md` §16.9) and is fixed; no thread-affinity gate remains on this branch. `frames_in_flight` depth (§13.9) still unpicked.
- [x] **Runtime snapshot (§9.4) — MERGE-BLOCKING gate — SATISFIED.** `RuntimeArchitectureV2.md` §16.9 is the as-built record: the extension in §16.3 (`ke_ecs` double-buffer + `swap_snapshots`) turned out unbuildable (flecs readonly mode is non-reentrant); what shipped is a runtime-owned extract + async `tick()` that joins the previous render before each extract. Sim/render genuinely pipeline (measured ~55-60% FPS gain on `09_many_lights`, not yet isolated from the extract-vs-shadow-entity substrate change in the same measurement). The shutdown crash that briefly held merge confidence was root-caused (an unjoined render task racing `UnloadModules`, not thread affinity) and fixed via `ke_runtime::flush_render` — no open blocker remains on the pipelining gate.
- [x] **PSO Mechanism 1 (§6) — dedup + never-stall half shipped.** `ke_render_service::get_or_create_pipeline` is the sole PSO authority; async compile emulated via a caller-supplied `ke_scheduler` (wgpu-native's own async primitive is unimplemented, confirmed on trunk); magenta fallback verified end-to-end visually (isolated to a single new object, pre-existing geometry unaffected). **Not built**: the ubershader (ubershader-vs-magenta compatibility split) — every miss falls back to magenta today regardless of compatibility. Mechanisms 2 (build-time manifest) and 3 (disk cache) remain ~0% — see §6.6.
- [ ] **Start G1**: render-v2 `build.zig` linking the webgpu distribution + a triangle through L3 from a `.slang` module.

**This doc is the contract.** When G1-G3 ship, every word in §3 + §4 + §5 should match the code or this doc gets revised.
