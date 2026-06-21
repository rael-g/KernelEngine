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
│       upscaler, hair, volumetric, etc. — each as a render-graph       │
│       pass set or a `ke_render` vtable extension)                     │
├──────────────────────────────────────────────────────────────────────┤
│  L6 — RenderGraph (already shipped — declares passes, resources,     │
│       dependencies; chooses execution order; handles barriers)        │
├──────────────────────────────────────────────────────────────────────┤
│  L5 — Mid-level passes & helpers                                      │
│       RenderPassBuilder / ComputePassHelper / ResourceUploader /      │
│       MaterialBinding / CommandRecorder / PipelineCache               │
├──────────────────────────────────────────────────────────────────────┤
│  L4 — Encoder & queue surface (CommandEncoder, RenderPass,           │
│       ComputePass, CommandBuffer — typed objects)                     │
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
- Each layer talks only to the layer immediately below. L7 *never* calls L3 directly.
- **L3 is the C ABI** — lives at `src/c/render/include/kernel_engine/render/gpu_device.h`, in the render domain alongside the existing `ke_render` (L7) contract. C ABI only; no privileged caller language (see §4.0).
- L3 extensions (ray tracing, mesh shaders, bindless, etc.) are queried from the device via `query_extension` — the engine knows nothing about them individually. See §4.5.
- **L4 and L5 are Zig** — they live in the render-v2 Zig core (location open, §13.2). They consume L3 in-language; they are *not* a second C ABI. A future C/C++ consumer of the device uses L3 directly.
- L7 lives in plugins (`KernelEngine.Render.<Feature>`) or in the game itself (a game can register its own render passes).
- L6 (RenderGraph) is **already shipped** — `src/c/render/include/kernel_engine/render/render_graph.h`. Reused as-is.

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

---

## 5. Mid-level abstractions — the key insight (L5, Zig)

This is where the architecture earns its keep. Every render technique above (RenderPass setup, draw issuance, resource binding) is **expressed in terms of these helpers, not directly against the device**. When we swap backends or evolve the device ABI, only a handful of Zig files change instead of 500 call sites. The helpers are Zig modules consuming the L3 C ABI in-language — they are not themselves a C ABI.

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

Owns PSO lifecycle. Detailed in §6.

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

When a PSO miss happens at draw time, the renderer **does not stall**. Instead:

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

## 7. Render graph (already shipped) — recap & integration

The render graph (`src/c/render/include/kernel_engine/render/render_graph.h` + impl) **stays as-is**, sitting at L6. Game code or feature modules declare passes; the graph resolves attachment dependencies, picks execution order, inserts barriers.

The change V2 brings: each render-graph pass is built using the **L5 mid-level helpers** instead of direct device calls. Today, passes call into the renderer which calls `gpu_device->`. After V2, passes use `RenderPassBuilder` / `ComputePassHelper`, never seeing the device. **No render-graph API change** — pure internal refactor of pass implementations.

**Integration with runtime**: each render-graph pass is registered as a runtime system (§9) pinned to the `ke.render` worker. The pass reads its input from `ke_ecs` via `ke_system_ctx` (camera/light/mesh by cid), the graph resolves attachment+barrier dependencies, the L5 helpers handle device-side recording. Post-R6, those reads route to the per-component snapshot back buffer automatically (§16 runtime doc); pre-R6, they read live storage and sim/render run serially.

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

---

## 9. Threading + runtime integration

`KernelEngine.Render.Modern` is a **runtime Module** (`IRuntimeModule` in C#, `ke_runtime_module_params` at the C ABI) — the same shape `KernelEngine.Render.Bgfx` uses today. The V2 renderer doesn't invent a new integration pattern; it slots into the locked one.

### 9.1 What the render module does NOT own

- **Component vocabulary.** `ke_camera_component`, the light components, `ke_mesh_component` are declared in the framework (`src/c/render/include/kernel_engine/render/components.h` + the framework's `ke_world_create` registration). The renderer **reads** these; it does not declare them.
- **Entity lifecycle.** Scene tree owns entities (`RuntimeArchitectureV2.md` §17.1). The renderer queries; it never spawns or destroys.
- **Scheduling.** The runtime owns phase ordering, wave building, dispatch. The renderer declares its systems' phase + access list + thread pinning.
- **A render thread of its own making.** No `std::thread` / Zig thread in the module. The scheduler's enki worker pool is the only source of parallelism (`RuntimeArchitectureV2.md` §8.4, project rule 5). The module pins its systems to a worker named `ke.render` — that is the entirety of its threading contract.

### 9.2 What the render module DOES own

- **The `ke_gpu_device` instance.** Created at module `on_load`, destroyed at `on_unload` (via the `ke_gpu_device_handle` owner-wrapper). Device + Queue + PipelineCache + the ResourceUploader's staging ring live here. Lifetime = module lifetime.
- **The render-graph passes** declared as runtime systems. Each pass is one `register_system` with `phase = KE_PHASE_UPDATE`/`POST_UPDATE`, `pinned_thread = <ke.render>`, an `access_list` of the components it reads, and an `execute` callback that records draws via the L5 helpers.
- **PSO compilation, shader hot reload, asset upload kickoff** — all dispatched to the shared `ke_task_scheduler` pool from inside pass execute bodies.

### 9.3 The component-snapshot boundary (R6+)

Locked in `RuntimeArchitectureV2.md` §16:

- Sim systems write `Transform`/`Mesh`/`Camera`/`Light` on the **live** side in `PreUpdate`/`Update`/`PostUpdate`.
- Render systems run in `Update`/`PostUpdate`. The scheduler infers from each render system's `access_list` that its reads route to the **snapshot** side.
- At phase boundaries the scheduler atomically rotates the snapshot index. Sim N+1 writes the new live side while render N reads the new snapshot side. No lock, no copy, no frame-packet object.
- Inference is automatic: any component touched by a render-phase system gets `KE_COMPONENT_DOUBLE_BUFFERED` on registration. Sim-only components stay single-buffered (zero overhead). Escape hatches `[NoDoubleBuffer]` / `[ForceDoubleBuffer]` for the rare exception.
- The L5 helpers don't care which side they read — they consume entity + cid via `ke_system_ctx_get`; snapshot routing happens one layer below in the ecs vtable.

### 9.4 Pre-R6 transitional state

R4 (current runtime scheduler) has no snapshot mechanism. Sim and render run serially; render-phase systems run on the pinned worker but read live storage. Functionally correct (render reads finalized sim state); leaves pipelining on the table. R6 lights it up by flipping the snapshot bits, transparently to render code written under §9.2.

**frame_packet does not exist in either state.** The LEGACY `*_render_system.cpp` extract-and-write-packet pattern was deleted in C-phase 4 of the runtime arc (`RuntimeArchitectureV2.md` §17.6.1). Render passes read components directly. (The old V2 draft called frame_packet "stable" — retracted, §12.)

### 9.5 Hot reload + asset upload threading

- **Shader hot reload**: a filesystem watcher (on a scheduler worker, not its own thread) detects `.slang` changes, kicks Slang compilation on the pool, invalidates affected PSO RAM cache entries. Next frame, the PSO request misses → Mechanism 1.
- **Asset upload**: `ResourceUploader.enqueueUpload(...)` callable from any thread; the staging ring is the sync point; the render-pinned pass issues the GPU copy on the encoder.
- **Background PSO compile**: same pool, same submit pattern; result lands in the cache, next frame's lookup finds it.

### 9.6 What game code touches

- Game code touches `Material`, `Mesh`, `Texture` (managed wrappers around opaque handles, refcounted, sim-safe). `meshNode.MeshHandle = ...` writes `MeshComponent.mesh` in the ecs — a sim-side write picked up next render frame via the snapshot.
- Game code **NEVER** touches `ke_gpu_device`. The device handle stays inside `KernelEngine.Render.Modern`. Even custom user passes declare component access lists and use the L5 helpers, not the device.

---

## 10. Migration plan — parallel build, Zig greenfield alongside CMake

V2 is a **new Zig lib built beside** the shipping bgfx renderer, not an in-place rewrite. The old renderer keeps shipping; V2 is a separate DI slot. Because V2 is greenfield, it is a natural early instance of incremental Zig adoption (`ZigMigrationPlan.md`): its own `build.zig` produces the V2 DLL and links the webgpu distribution, **coexisting** with the CMake tree that builds everything else. No full build-system swap is a prerequisite.

### Phase G0 — This doc + headers re-homed (done)
Doc carried onto `feat/render-v2-zig`; Slang shaders + L3 C ABI headers ported and reshaped to current conventions (§4.0). C++ impl discarded.

### Phase G1 — Slang spike + webgpu triangle (1-2 sessions)
- `slangc` in the toolchain; `compile_shaders.py` `.slang` path → SPIR-V.
- The render-v2 `build.zig` links `eliemichel/WebGPU-distribution`; a Zig `ke_gpu_device_webgpu` fills enough of the L3 vtable to clear + present.
- Render a triangle from a `.slang`-compiled module through the full L3 surface. No engine integration. **Hard gate: triangle renders.**

### Phase G2 — L4/L5 mid-level (Zig) (3-5 sessions)
- Implement `CommandEncoder`/`RenderPass`/`ComputePass` (L4) and `RenderPassBuilder`/`ComputePassHelper`/`ResourceUploader`/`MaterialBinding`/`CommandRecorder`/`PipelineCache` (L5) as Zig modules over L3.
- Render-graph passes (L6, already shipped) re-pointed to use L5.

### Phase G3 — Runtime module + first engine scene (2-3 sessions)
- `KernelEngine.Render.Modern` runtime module: device at `on_load`, passes registered as systems pinned to `ke.render`, reads components via `ke_system_ctx`.
- `example_01` opts into Modern via DI; both renderers selectable. **Hard gate: example_01 visually matches Bgfx.**

### Phase G4 — PSO Mechanism 1 (ubershader + magenta) (3-4 sessions)
`PipelineCache` (RAM only); build-time ubershader (PBR forward + shadow + depth prepass); magenta placeholder; background compile via the worker pool; hot reload invalidates RAM entries. **Goal: dev iteration never stalls.**

### Phase G4.1 — PSO Mechanism 3 (disk cache + driver hash) (2 sessions)
`driver_hash` at boot; cache dir per (game, engine_ver, driver); lazy load → create_pipeline_from_blob; write on compile success; invalidate on hash change.

### Phase G4.2 — PSO Mechanism 2 (build-time manifest) (3-4 sessions)
`ke build manifest` CLI verb; walk materials; cartesian product → `psos.manifest`; first-launch compile pass; coverage metric vs examples.

### Phase G5 — Feature parity sweep (open-ended)
Port one feature at a time: PBR materials, shadow mapping, IBL, tone mapping, post chain. Each = (a) port the Slang shader, (b) port the render-graph pass to Modern. Bgfx untouched; Modern bugs roll back via DI.

### Phase G6 — Cut over default; deprecate Bgfx
Default DI swap. Bgfx becomes "legacy stable" (critical fixes only). Delete after 3+ months of Modern as default with no regressions.

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
2. **Zig source layout for L2/L4/L5.** No Zig source tree exists yet — this renderer is the first. Proposal: a `src/zig/render/` tree parallel to `src/c` / `src/cpp` (backend, core, module subdirs), with the C ABI headers staying in `src/c/render/include/`. **PO decision — no precedent to copy.**
3. **L4/L5 surface confirmation.** This doc collapses the previous branch's double recording surface (§4.0.5) and inline forwarders (§4.0.1). Confirm before the headers are treated as final.
4. **Disk PSO cache location** — per-user (`%LOCALAPPDATA%`) keyed by project + engine version. Lock during G4.1.
5. **GPU handle type safety** — bare `uint64_t` (WebGPU style) vs struct-wrapped `{ uint64_t id; }` (engine `handles.h` style). Lock during G1.
6. **Bindless** — WebGPU is conservative; Vulkan/D3D12 allow effectively-bindless descriptor sets. Exposed via the `ke_gpu_bindless` extension (§4.5). Lock the extension API shape when the first GPU-driven pass needs it.
7. **Slang language version pinning** — pin a Slang version in the toolchain, bump deliberately. Document alongside the Zig version pin.

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
- [ ] Lock §13 open questions — chiefly the Zig source layout (§13.2) and the L4/L5 surface confirmation (§13.3) — before G1.
- [ ] **Start G1**: render-v2 `build.zig` linking the webgpu distribution + a triangle through L3 from a `.slang` module.

**This doc is the contract.** When G1-G3 ship, every word in §3 + §4 + §5 should match the code or this doc gets revised.
