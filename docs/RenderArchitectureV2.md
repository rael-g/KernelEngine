# Render Architecture V2 — utopian renderer layered on a WebGPU-style core

**Status**: Accepted at design level (2026-06). Implementation lands per §10's G-phase plan, parallel to the existing `KernelEngine.Render.Bgfx` renderer.
**Audience**: Engine maintainer + future render plugin authors + game devs writing custom shaders/passes.
**Companion doc**: [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md) — defines `ke_runtime` (the scheduler), `ke_ecs` (storage), `ke_world` (framework aggregator), `components.h` (the component vocabulary the renderer reads), §16 (per-component snapshot pipelining), and §17 (the V1 merge arc that already deleted the LEGACY `*_render_system.cpp` extract path frame_packet relied on).

**Integration model — the short version**: the renderer is a runtime **Module** that pins its passes to a worker named `ke.render` and reads `Camera`/`Light`/`Mesh` components straight from `ke_ecs` via `ke_system_ctx`. There is no extract phase that writes a frame packet; once R6 wires up the per-component snapshot back-buffer (§16 of the runtime doc), render passes read the snapshot side while sim writes the live side. Pre-R6 transitional state runs sim and render serially on the same world — no pipelining, no separate handoff buffer. Frame packet is **not part of the V2 contract**.

---

## 1. Purpose

The current renderer (`KernelEngine.Render.Bgfx` + `Render.Core`) is **functional and shipping** but has structural problems that will only get worse as we add modern techniques:

1. **`GpuDevice` API is OpenGL/DX11-era stateful** — `SetState` / `SetUniform` / `Submit` per draw. The control bgfx gives us over Vulkan memory + barriers is *literally not used* because the abstraction above it pretends GL exists.
2. **Hundreds of direct `gpu_device->` calls scattered across `core_renderer.cpp`** — any change to the device API breaks 500 sites at once. Swapping the device is a 3-month project.
3. **No PSO management** — bgfx hides pipeline state objects entirely. When we move to a backend that exposes them (WebGPU-style), we'll either copy Godot's mistake (lazy compile + runtime stalls forever) or design the **three-mechanism solution** (ubershader fallback + build-time manifest + per-machine disk cache — see §6). The mechanisms compose; copying just one (cache without manifest, or manifest without ubershader) leaves the player with stutters. We need to design all three *now*, before the problem exists.
4. **Shader pipeline is bgfx `.sc`** — a preprocessor over GLSL. No modules, no generics, no interfaces. Slang exists; Slang is the future; the migration has to happen at some point.
5. **No mid-level abstractions** — the renderer is "high-level features call the low-level device directly". There's no `RenderPass` / `ComputePass` / `MaterialBinding` layer to absorb backend changes.

This doc defines the **target renderer architecture** — what we build *alongside* the current one, as a new plugin (`KernelEngine.Render.Modern`), so the old one keeps shipping while the new one matures. When V2 reaches feature parity, swap default. The bgfx-based renderer survives as a fallback DI choice (and a real-world test that we didn't accidentally bake new-stack assumptions into game code).

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
│       RenderPass / ComputePass / ResourceUploader / MaterialBinding   │
│       / CommandRecorder / PipelineCache                               │
├──────────────────────────────────────────────────────────────────────┤
│  L4 — Encoder & queue surface (CommandEncoder, Queue, Sync)          │
├──────────────────────────────────────────────────────────────────────┤
│  L3 — `ke_gpu_device` C ABI (WebGPU-style — Device, Buffer,          │
│       Texture, Sampler, ShaderModule, Pipeline, BindGroup,            │
│       CommandBuffer)                                                  │
├──────────────────────────────────────────────────────────────────────┤
│  L2 — Backend impl (Vulkan / D3D12 / Metal / WebGPU)                 │
├──────────────────────────────────────────────────────────────────────┤
│  L1 — OS / driver                                                     │
└──────────────────────────────────────────────────────────────────────┘
```

**Rules of the road**:
- Each layer talks only to the layer immediately below. L7 *never* calls L3 directly.
- L3 is the **C ABI** that lives in `src/c/kernel/include/`. Promoting `gpu_device` to the kernel was already discussed — this is where it lands.
- L4 and L5 live in `src/cpp/render/core/` (the agnostic core, no backend-specific code).
- L7 lives in plugins (`KernelEngine.Render.<Feature>`) or in the game itself (a game can register its own render passes).
- L6 (RenderGraph) is **already shipped** — see Done.md `[F.RC2]`. Reused as-is.

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

### 3.9 Mid-level: RenderPassHelper, ComputePassHelper, MaterialBinding, ResourceUploader, CommandRecorder

These live above the device but below render-graph and high-level features. **The user's insight — the most important architectural decision in this doc.** Detailed in §5.

---

## 4. C ABI — `ke_gpu_device` promoted to kernel

Lives at `src/c/kernel/include/kernel_engine/kernel/render/gpu_device.h`. Replaces the current `src/cpp/render/contract/include/gpu_device.hpp` (C++ class).

### 4.1 Opaque handles

```c
typedef struct ke_gpu_device         ke_gpu_device;
typedef struct ke_gpu_queue          ke_gpu_queue;
typedef struct ke_gpu_command_encoder ke_gpu_command_encoder;
typedef struct ke_gpu_command_buffer  ke_gpu_command_buffer;
typedef struct ke_gpu_render_pass     ke_gpu_render_pass;
typedef struct ke_gpu_compute_pass    ke_gpu_compute_pass;

typedef uint64_t ke_gpu_buffer;
typedef uint64_t ke_gpu_texture;
typedef uint64_t ke_gpu_texture_view;
typedef uint64_t ke_gpu_sampler;
typedef uint64_t ke_gpu_shader_module;
typedef uint64_t ke_gpu_pipeline;
typedef uint64_t ke_gpu_bind_group_layout;
typedef uint64_t ke_gpu_bind_group;
```

Resources are uint64 handles (not raw pointers) — same pattern we use today, decouples app from backend memory layout.

### 4.2 Device vtable (essential surface — full surface enumerated when impl starts)

```c
typedef struct ke_gpu_device {
    void *handle;

    // Queue access
    ke_gpu_queue * (*get_default_queue)(ke_gpu_device *self);

    // Resource creation (each returns 0 / KE_GPU_INVALID_HANDLE on failure)
    ke_gpu_buffer        (*create_buffer)(ke_gpu_device *self, const ke_gpu_buffer_params *p);
    ke_gpu_texture       (*create_texture)(ke_gpu_device *self, const ke_gpu_texture_params *p);
    ke_gpu_texture_view  (*create_texture_view)(ke_gpu_device *self, ke_gpu_texture tex, const ke_gpu_texture_view_params *p);
    ke_gpu_sampler       (*create_sampler)(ke_gpu_device *self, const ke_gpu_sampler_params *p);
    ke_gpu_shader_module (*create_shader_module)(ke_gpu_device *self, const ke_gpu_shader_module_params *p);
    ke_gpu_pipeline      (*create_render_pipeline)(ke_gpu_device *self, const ke_gpu_render_pipeline_params *p);
    ke_gpu_pipeline      (*create_compute_pipeline)(ke_gpu_device *self, const ke_gpu_compute_pipeline_params *p);
    ke_gpu_bind_group_layout (*create_bind_group_layout)(ke_gpu_device *self, const ke_gpu_bind_group_layout_params *p);
    ke_gpu_bind_group    (*create_bind_group)(ke_gpu_device *self, const ke_gpu_bind_group_params *p);

    // Resource destruction (deferred to next safe frame internally)
    void (*destroy_buffer)(ke_gpu_device *self, ke_gpu_buffer h);
    void (*destroy_texture)(ke_gpu_device *self, ke_gpu_texture h);
    // ... etc per resource type

    // Encoder lifecycle
    ke_gpu_command_encoder * (*create_command_encoder)(ke_gpu_device *self);

    // Mapped writes (for streaming uploads — see ResourceUploader §5.3)
    void * (*map_buffer)(ke_gpu_device *self, ke_gpu_buffer h, size_t offset, size_t size);
    void   (*unmap_buffer)(ke_gpu_device *self, ke_gpu_buffer h);

    // Capabilities (RT support? mesh shaders? bindless? variable rate shading?)
    void (*get_capabilities)(ke_gpu_device *self, ke_gpu_capabilities *out);

    void (*destroy)(ke_gpu_device *self);
} ke_gpu_device;
```

### 4.3 CommandEncoder + Pass vtables

```c
typedef struct ke_gpu_command_encoder {
    void *handle;

    ke_gpu_render_pass *  (*begin_render_pass)(ke_gpu_command_encoder *self,
                                                const ke_gpu_render_pass_params *p);
    ke_gpu_compute_pass * (*begin_compute_pass)(ke_gpu_command_encoder *self);

    // Inter-pass / inter-resource barriers (explicit; WebGPU calls these "implicitly")
    // Optional — backends that auto-barrier can stub.
    void (*pipeline_barrier)(ke_gpu_command_encoder *self, const ke_gpu_barrier *b);

    // Buffer-to-buffer / buffer-to-texture / texture-to-texture copies
    void (*copy_buffer_to_buffer)(ke_gpu_command_encoder *self, ke_gpu_buffer src, size_t src_offset,
                                  ke_gpu_buffer dst, size_t dst_offset, size_t size);
    void (*copy_buffer_to_texture)(ke_gpu_command_encoder *self, /* ... */);

    ke_gpu_command_buffer * (*finish)(ke_gpu_command_encoder *self);
    void (*destroy)(ke_gpu_command_encoder *self);
} ke_gpu_command_encoder;

typedef struct ke_gpu_render_pass {
    void *handle;

    void (*set_pipeline)(ke_gpu_render_pass *self, ke_gpu_pipeline pipe);
    void (*set_bind_group)(ke_gpu_render_pass *self, uint32_t group_index,
                           ke_gpu_bind_group bg, const uint32_t *dynamic_offsets, uint32_t dyn_count);
    void (*set_vertex_buffer)(ke_gpu_render_pass *self, uint32_t slot, ke_gpu_buffer b, size_t offset);
    void (*set_index_buffer)(ke_gpu_render_pass *self, ke_gpu_buffer b, ke_gpu_index_format fmt, size_t offset);
    void (*set_viewport)(ke_gpu_render_pass *self, float x, float y, float w, float h, float min_d, float max_d);
    void (*set_scissor)(ke_gpu_render_pass *self, int32_t x, int32_t y, uint32_t w, uint32_t h);

    void (*draw)(ke_gpu_render_pass *self, uint32_t vert_count, uint32_t inst_count,
                 uint32_t first_vert, uint32_t first_inst);
    void (*draw_indexed)(ke_gpu_render_pass *self, uint32_t idx_count, uint32_t inst_count,
                         uint32_t first_idx, int32_t base_vert, uint32_t first_inst);
    void (*draw_indirect)(ke_gpu_render_pass *self, ke_gpu_buffer indirect, size_t offset);
    // mesh shader draws when KE_GPU_CAP_MESH_SHADERS

    void (*end)(ke_gpu_render_pass *self);
} ke_gpu_render_pass;

typedef struct ke_gpu_compute_pass {
    void *handle;

    void (*set_pipeline)(ke_gpu_compute_pass *self, ke_gpu_pipeline pipe);
    void (*set_bind_group)(ke_gpu_compute_pass *self, uint32_t group_index, ke_gpu_bind_group bg,
                           const uint32_t *dyn_offsets, uint32_t dyn_count);
    void (*dispatch)(ke_gpu_compute_pass *self, uint32_t x, uint32_t y, uint32_t z);
    void (*dispatch_indirect)(ke_gpu_compute_pass *self, ke_gpu_buffer indirect, size_t offset);

    void (*end)(ke_gpu_compute_pass *self);
} ke_gpu_compute_pass;
```

### 4.4 First impl: `KernelEngine.Render.Modern.Vulkan` (or `.Wgpu`)

Two reasonable starting impls:

1. **Direct Vulkan**: write the impl as a raw `VkDevice` wrapper. Maximum control, most code, deepest learning. Aligns with the user's stated discomfort that we're using Vulkan via bgfx but not getting Vulkan's actual benefits.

2. **wgpu-native** (Rust-implemented WebGPU runtime, C bindings exposed): pre-built, mature, cross-platform via Vulkan/D3D12/Metal automatically. Smaller impl scope (we mainly translate `ke_gpu_*` → `wgpu_*`). Sacrifices some control but ships much faster.

**Recommendation**: start with **wgpu-native** for the R-equivalent spike. Validates the API shape end-to-end in 1-2 sessions. If we hit a wall (capability not exposed, perf issue), we have direct Vulkan as fallback project. wgpu's API was *literally the design source* for the C ABI above, so the translation is near-mechanical. This is "plug the wheel" doctrine applied to the device backend itself.

Caveat for the user: wgpu-native ships as a `.dll` we link against; it's a Rust runtime under the hood. Adds a binary dependency (~5MB). If the user prefers zero Rust in the engine, direct Vulkan is the answer; longer road but full control.

---

## 5. Mid-level abstractions — the user's key insight

This is where the architecture earns its keep. Every render technique above (RenderPass setup, draw issuance, resource binding) is **expressed in terms of these helpers, not directly against the device**. When we swap backends or evolve the device ABI, only ~5 files change instead of 500.

### 5.1 `RenderPassBuilder` / `RenderPassHelper`

Wraps the device's RenderPass with material/pipeline-aware ergonomics. Caller never touches viewport math, pipeline switching, or bind group resolution.

```cpp
// Pseudocode — actual API designed during R-equivalent
RenderPassBuilder pass(device, encoder, {
    .color_targets = { swapchain_view },
    .depth_target  = depth_view,
    .clear_color   = {0.1, 0.1, 0.2, 1.0},
});

for (auto& [mesh, mat, xform] : visible_meshes) {
    pass.bind_material(mat);        // resolves PSO + bind groups; PSO miss → placeholder
    pass.set_transform(xform);      // updates per-draw uniform
    pass.draw_mesh(mesh);           // sets vertex/index buffer + draw call
}

pass.end();  // emits ke_gpu_render_pass.end + destroy
```

The pass tracks current pipeline / bind groups internally and elides redundant binds (Vulkan/D3D12 don't deduplicate this automatically).

### 5.2 `ComputePassHelper`

Same idea for compute.

```cpp
ComputePassHelper cpass(device, encoder);
cpass.bind_shader(light_cull_shader);
cpass.set_storage_buffer(0, light_buffer);
cpass.set_storage_image(1, tile_grid);
cpass.dispatch(tiles_x, tiles_y, 1);
cpass.end();
```

The helper handles barrier insertion if the backend needs it (already covered by render-graph at the higher level — see §7).

### 5.3 `ResourceUploader`

Schedules CPU→GPU uploads off the hot path. Critical for streaming and large asset loads.

- **Staging ring buffer** owned by the uploader (configurable size, e.g. 64MB).
- Caller `enqueue_upload(buffer, data, size)` returns immediately.
- Uploader copies into staging on a worker thread, records the copy command on the encoder later.
- Multi-frame in flight: ring buffer rotates per frame; never overwrites in-use staging memory.

Replaces the current "synchronous upload via map/unmap on render thread" pattern that blocks render whenever an asset loads.

### 5.4 `MaterialBinding`

Given a `Material` (engine-level concept: shader + parameter values + texture refs), resolves to:
- A cached `ke_gpu_pipeline` (via `PipelineCache`, §6)
- A cached or freshly-built `ke_gpu_bind_group` for the material's parameters
- The per-draw uniforms it needs

One `material_binding.apply_to(render_pass)` call replaces dozens of low-level bind calls.

### 5.5 `CommandRecorder`

Sorts queued draws by material/depth/whatever, builds the command buffer in one pass, submits. The renderer enqueues draws "logically" (mesh, material, transform); the recorder decides issue order.

This is where future GPU-driven rendering plugs in: instead of one CPU-side recorder, the recorder builds a draw-call buffer + dispatches indirect from a compute shader.

### 5.6 `PipelineCache`

Owns PSO lifecycle. Detailed in §6.

---

## 6. PSO architecture — three mechanisms working together

The Godot mistake worth understanding precisely: it isn't that they "forgot" to cache PSOs; it's that their architecture allows **runtime shader generation via script**, and PSO state spreads across forward/shadow/gbuffer/depth-prepass passes without explicit declaration. Without manifest constraints, the engine cannot enumerate "all PSOs this game will need" at build time → can only compile lazily → first time each combination is hit → 100ms-2s stall → player sees hitches everywhere.

Our doctrine is the inverse, and it is the central design constraint of the renderer:

> **The set of PSOs a game needs MUST be statically derivable from the project. The engine refuses runtime shader generation.**

This is the trade-off Unreal made (knowingly) and Godot didn't (the architecture grew before PSOs existed in GL ES). It's what separates "smooth shipped game" from "stutters everywhere".

What this means for game-dev flexibility — exactly what's allowed:

✅ Write any Slang shader, any vertex layout, any blend mode, any depth state
✅ Have thousands of materials authored in source / scene files / CLI
✅ Swap materials between objects dynamically (PSO already exists for either)
✅ Use advanced shading (clearcoat, sheen, hair, subsurface, custom passes)
✅ Modders can ship new materials — one-time compile per new material per machine

❌ Build shader source as a string at runtime and compile it
❌ Permute PSO state (blend, depth, formats) based on runtime conditions

In practice 99% of game devs never hit the constraint — nobody concatenates shader strings at runtime outside tech demos. The 1% who do can opt-in to Mechanism 1 below with documented performance warning.

With that doctrine in place, **three independent mechanisms** make PSO compilation invisible to the player. They are NOT the same thing; conflating them is what makes most engine PSO docs hand-wavy.

### Mechanism 1 — Ubershader fallback (runtime safety net)

When a PSO miss happens at draw time, the renderer **does not stall**. Instead:

1. Look up the request in the ubershader compatibility map
2. **Ubershader-compatible** (PBR forward, shadow caster, depth prepass, basic compute): render with the ubershader pipeline — a single large precompiled PSO that handles ~95% of common cases via dynamic branches and uniform-driven feature toggles. Visually nearly identical to the specialized PSO; ~10-20% slower per draw due to branchier shader.
3. **Not ubershader-compatible** (tessellation, mesh shader, RT pipeline, custom user passes): render with a **magenta placeholder PSO** — same vertex layout, fragment outputs `vec4(1, 0, 1, 1)`. Obviously wrong, debuggable, never silent.
4. In both cases: enqueue background compile on the worker pool.
5. Next frame: if compile finished, swap to real PSO. No further fallback needed.

**Ubershader vs magenta — when each fires**:

| Material type | Fallback | Player notices? |
|---|---|---|
| Standard PBR forward | Ubershader | No (looks identical, slightly slower for 1-2 frames) |
| Shadow casting | Ubershader | No |
| User shader (clearcoat / sheen / SSS) | Ubershader | Barely (effect missing for 1-2 frames) |
| Hair (Marschner) | Magenta | Yes (this is rare enough to flag) |
| Custom user pass | Magenta | Yes |

The ubershader itself is a build-time artifact: a Slang program parameterized over a large but fixed feature set, compiled into ONE PSO at build time, ships with the game. It exists precisely so Mechanism 1 has a real fallback for the common case.

This is what Godot 4.4+ is implementing — they got to the right answer, just late. UE5 has had ubershader fallback for years.

**Doctrine**: ubershader is the *expected* fallback in dev iteration (modder content too). Magenta is the *debug visible* fallback that signals "something exotic happened that wasn't predicted". A shipped release game should never show magenta — Mechanism 2 catches everything ubershader can't cover.

### Mechanism 2 — Build-time PSO manifest (the doctrine made concrete)

Before the game ships, the engine extracts the complete PSO set from the project declaration. The CLI command `ke build manifest` walks the project and emits a manifest.

**What the CLI walks**:
- All `.material` files referenced anywhere in scenes / code / Project
- The set of passes each material participates in (declared per material via metadata, or defaulted per shader type — `IMaterial` → ForwardLit + Shadow + DepthPrepass; `IPostEffect` → fullscreen; etc.)
- All vertex layouts used (engine-defined: Static, Skinned, etc., plus user-declared layouts)
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

[[pso]]
key = "water+shadow_caster+static+v0"
shader_module = "shaders/water.slang"
entry_point_vs = "VertexMain"
pass = "ShadowCaster"
# ... etc

# Typical project: 50 materials × 4 passes × 2 vertex layouts × 1 variant = 400 PSOs
```

**Generated**, never written by hand. Lives in the project at `build/psos.manifest`. Regenerated on `ke build` whenever any material / scene / project file changes.

**Game ships the manifest**: it's part of the install package. Player's machine reads it on first launch.

**Refusing runtime shader generation isn't punitive — it's the trade that enables this manifest existing.** A game that needs runtime shader gen explicitly disables the manifest constraint per material and accepts Mechanism 1 fallbacks permanently for those materials.

### Mechanism 3 — Per-machine disk cache (PSO bytecode storage)

PSO compilation output is **driver-specific bytecode**. NVIDIA 555 compiled PSOs don't work on NVIDIA 556. RTX 4090 PSOs don't work on RTX 3060. Windows PSOs don't work on Linux. So compilation must happen on the player's machine, once per (driver version × GPU × OS) combination.

**Cache location**: `~/.cache/kernelengine/<game_id>/<engine_version>/<driver_hash>/` (Windows: `%LOCALAPPDATA%\KernelEngine\<game_id>\<engine_version>\<driver_hash>\`).
**Cache contents**: one binary file per PSO key, named by the key's hash. Bytecode blob + minimal metadata for validation.
**Driver hash**: hash of `(GPU vendor, GPU device, driver version, OS, OS version)`. Recomputed each boot; mismatch invalidates the cache.

**First launch flow** (per machine):
```
1. Read manifest (Mechanism 2)
2. Compute driver_hash
3. Check disk cache for current driver_hash
4. For PSOs missing from disk cache:
       Show "Optimizing for your system (1/750)" UI
       Compile on worker pool (8-16 threads simultaneous)
       Write bytecode to disk as each completes
5. All compiled → done. Splash screen complete.
   Game starts. Zero PSO compilation will happen in gameplay.
```

Typical timing: 750 PSOs × ~500ms each / 8-thread pool = **~45 seconds, one time per install + driver-update**.

**Subsequent launches**:
```
1. Read manifest
2. driver_hash matches → all PSOs already on disk
3. Lazy load from disk as the renderer requests them (microseconds each — memcpy + device->create_pipeline from bytecode)
4. Zero compilation. Zero stalls.
```

**Driver update detection**: `driver_hash` mismatch → re-run first-launch flow. Game shows splash again, user understands why ("Driver updated, re-optimizing").

**Engine update**: `engine_version` is part of the cache path → fresh cache for new engine version. Players who update the engine see the splash once.

### How the three mechanisms compose

```
┌──────────────────────────────────────────────────────────────────────┐
│  BUILD-TIME (developer machine — `ke build`)                         │
│                                                                      │
│   project → walk materials + passes + layouts →                      │
│   compute cartesian product → emit psos.manifest                     │
│   (Mechanism 2 — runs whenever materials/passes change)              │
└──────────────────────────────┬───────────────────────────────────────┘
                               ↓ manifest ships in game install
┌──────────────────────────────────────────────────────────────────────┐
│  FIRST LAUNCH (per machine × engine_version × driver_hash)           │
│                                                                      │
│   read manifest → spawn worker pool →                                │
│   compile every PSO not already on disk → write bytecode →           │
│   "Optimizing 750/750... done"                                       │
│   (Mechanism 3 — runs once per install + driver update)              │
└──────────────────────────────┬───────────────────────────────────────┘
                               ↓ steady state
┌──────────────────────────────────────────────────────────────────────┐
│  GAMEPLAY — every frame, every draw                                  │
│                                                                      │
│   PSO requested by mid-level helper:                                 │
│     ├─ in RAM cache? (already loaded this session)                   │
│     │      → return (microseconds)                                   │
│     ├─ in disk cache? (compiled previously)                          │
│     │      → mmap + device->create_pipeline_from_blob (1ms)          │
│     │      → cache in RAM, return                                    │
│     └─ neither (RARE post-release; common in dev iteration):         │
│         ├─ ubershader compatible? → use ubershader, compile bg       │
│         └─ exotic? → magenta placeholder, compile bg                 │
│   (Mechanism 1 — backstop, never the primary path in shipped game)   │
└──────────────────────────────────────────────────────────────────────┘
```

Each mechanism owns a distinct concern:

| Mechanism | Owns | Runs when | Scope |
|---|---|---|---|
| 1 — Ubershader / magenta fallback | The "we don't stall, ever" guarantee | Every draw that misses cache | Per draw |
| 2 — Build-time manifest | The "we know what PSOs we need" knowledge | Every `ke build` | Per project, per build |
| 3 — Per-machine disk cache | The "actually compiled bytecode" storage | First launch, driver update | Per machine, per engine_ver, per driver |

### 6.4 Operational modes

**Dev iteration** (Pong loop, debug build, `dotnet watch`):
- Manifest may not exist yet (or is stale)
- Disk cache exists but is partial
- Mechanism 1 carries the load: PSO misses fallback to ubershader, compile in background, swap next frame
- Hot reload of `.slang` files invalidates affected PSO cache entries → next request recompiles
- Goal: never break the dev iteration loop

**Beta / playtest builds**:
- Manifest is generated and shipped
- First-time playtesters experience one first-launch compile (~45s)
- Mechanism 1 catches any manifest gaps (logged as warnings — "this PSO wasn't in the manifest, you may have missed declaring a material somewhere")

**Shipped release**:
- Manifest is complete (gaps fixed during beta)
- First launch on every player machine compiles manifest → disk cache
- Mechanism 1 only fires for modder content / runtime-opt-in dynamic materials
- Goal: zero unexpected stalls in gameplay, ever

### 6.5 Cache invalidation

| Event | Result |
|---|---|
| Edit a `.slang` file (dev) | RAM cache: invalidate every PSO referencing it. Disk cache: invalidate only if hash of compiled bytecode changed. |
| Driver update (player) | `driver_hash` mismatch → fresh first-launch flow |
| Engine version update (player) | Cache directory changes (`<engine_ver>` in path) → fresh first-launch flow |
| Game update (new materials in patch) | Manifest changes; new PSOs missing from disk → compile on next launch (much smaller than first-launch — only the diff) |
| Mod installs new material | Manifest unchanged; PSO miss at runtime → Mechanism 1 fallback + background compile, then add to disk cache for future launches |

### 6.6 Implementation breakdown (each mechanism is its own project)

These ship in sequence, not as one card:

| Phase | Mechanism | Scope | Effort |
|---|---|---|---|
| Initial G6 | Mechanism 1 (ubershader + magenta) | Make dev iteration painless. Ubershader covers PBR forward + shadow + depth prepass. Magenta for the rest. | ~3-4 sessions |
| G6+1 | Mechanism 3 (disk cache + driver hash) | Bytecode persists across launches. Compile on first launch. RAM cache layer in front. | ~2 sessions |
| G6+2 | Mechanism 2 (build-time manifest) | `ke build manifest` CLI verb. Walks materials, emits TOML manifest. First-launch compile pass driven by manifest. | ~3-4 sessions |
| G6+3 | Polish — manifest coverage metrics, "compile budget" reporting per build, driver-update UX | ~1-2 sessions |

Mechanism 1 alone is enough to ship M1-M2 engine demos. Mechanism 3 is needed before any non-trivial game (PSO count grows fast). Mechanism 2 is needed before shipping any release game.

---

## 7. Render graph (already shipped) — recap & integration

The render graph (`src/c/kernel/include/kernel_engine/kernel/render/render_graph.h` + impl) **stays as-is**, sitting at L6. Game code or feature modules declare passes; the graph resolves attachment dependencies, picks execution order, inserts barriers.

The change V2 brings: each render-graph pass is built using the **L5 mid-level helpers** instead of direct device calls. Today, render-graph passes call into `core_renderer.cpp` which calls into `gpu_device->`. After V2, render-graph passes use `RenderPassBuilder` / `ComputePassHelper`, never seeing the device.

No render-graph API change. Pure internal refactor of pass implementations.

**Integration with runtime**: each render-graph pass is registered as a runtime system (see §9) pinned to the `ke.render` worker. The pass reads its input from `ke_ecs` via `ke_system_ctx` (camera/light/mesh components by cid), the graph resolves attachment+barrier dependencies, the L5 helpers handle the device-side recording. Post-R6, those `ke_system_ctx` reads route to the per-component snapshot back buffer automatically (§16 of the runtime doc); pre-R6, they read the live storage and sim/render run serially.

---

## 8. Shader pipeline — Slang as canonical source

### 8.1 Choice rationale

- **Modules + interfaces + generics** at the shader level — engine ships `ke_spatial.slang` declaring `interface IMaterial { void vertex(inout VertexInfo); void fragment(inout MaterialState); }`. Users implement the interface; Slang's generics + interfaces instantiate the engine's main entry point with the user impl.
- **One source → all backends**: SPIR-V (Vulkan), DXIL (D3D12), MSL (Metal), HLSL (D3D11 legacy), GLSL (legacy). Slang ships official cross-compilers; we don't write any of this.
- **Reflection**: Slang exposes its reflection API — we feed PSO layout, bind group bindings, push constants etc. from the same source, no hand-maintained sidecars.
- **AAA-validated**: NVIDIA, UE5, others use Slang in production.

### 8.2 Build integration

`scripts/compile_shaders.py` currently calls `shaderc` for bgfx `.sc`. Adds a parallel path:
- `*.slang` files → invoke `slangc` → emit `.spv` / `.dxil` / `.msl` to `build/.../shaders/compiled/<backend>/<name>.<ext>`.
- Renderer V2 loads bytecode at runtime via `device->create_shader_module(bytecode_blob)`.

Both pipelines coexist during migration: `.sc` for engine legacy shaders during Bgfx-renderer life, `.slang` for new code + everything in V2.

### 8.3 User-facing material shaders

```hlsl
// game/materials/water.slang
import ke_spatial;

struct WaterMaterial : IMaterial {
    Texture2D normalMap;
    SamplerState samp;
    float waveSpeed;

    void vertex(inout VertexInfo v) {
        v.position.y += sin(v.position.x * 0.1 + time * waveSpeed) * 0.5;
    }
    void fragment(inout MaterialState s) {
        float3 n = normalMap.Sample(samp, s.uv).xyz * 2 - 1;
        s.normal = mul(s.tbn, n);
        s.albedo = float3(0.1, 0.3, 0.5);
        s.roughness = 0.05;
    }
}
```

Engine's `ke_spatial.slang` declares the main entry point parameterized over `IMaterial`; the build step specializes it for `WaterMaterial`. Game dev sees only "implement these two methods". Closest analogue is Godot's `shader_type spatial` minus the parser + framework lock-in.

---

## 9. Threading + runtime integration

`KernelEngine.Render.Modern` is a **runtime Module** (`IRuntimeModule` in C#, `ke_runtime_module_params` at the C ABI). The same shape `KernelEngine.Render.Bgfx` already uses today in `01_runtime_clear_color` and onward — the V2 renderer doesn't invent a new integration pattern; it slots into the one that's locked.

### 9.1 What the render module does NOT own

- **Component vocabulary**. `ke_camera_component`, `ke_directional_light_component`, `ke_point_light_component`, `ke_spot_light_component`, `ke_mesh_component` are declared in `kernel/framework/components.h` and registered in the ecs by the framework's `ke_world_create` (or by an alternative framework — anyone shipping their own). The renderer **reads** these components; it does not declare them.
- **Entity lifecycle**. Scene tree owns entities (per `RuntimeArchitectureV2.md` §17.1). The renderer queries existing entities; it never spawns or destroys.
- **Scheduling**. The runtime owns phase ordering, wave building, dispatch. The renderer declares its systems' phase + access list + thread pinning and lets the scheduler call back when it's time.
- **A separate render thread of its own making**. There is no `std::thread` inside the render module. The scheduler's enki worker pool is the only source of parallelism in the engine (per `RuntimeArchitectureV2.md` §8.4). The render module pins its systems to a worker named `ke.render`, and that's the entirety of its threading contract.

### 9.2 What the render module DOES own

- **`ke_gpu_device` instance**. Created at module `on_load`, destroyed at `on_unload`. The Device + Queue + the PipelineCache + the ResourceUploader's staging ring live here. Lifetime = module lifetime.
- **The render-graph passes** declared as runtime systems. Each pass is one `register_system` call with:
  - `phase = KE_PHASE_UPDATE` (or `KE_PHASE_POST_UPDATE`; the renderer is the consumer-side phase, post-sim)
  - `pinned_thread = <index-of-"ke.render">`
  - `access_list` declaring the components it reads (Camera, Mesh, Light, etc. by cid)
  - `execute` callback that records draws via the L5 helpers
- **PSO compilation, shader hot reload, asset upload kickoff**. All dispatched to the shared `ke_task_scheduler` pool from inside pass execute bodies — same worker pool everything else uses.

### 9.3 The component-snapshot boundary (R6+)

The transition is locked in `RuntimeArchitectureV2.md` §16. Restated here because it's the central piece of how render integrates with sim:

- Sim systems (game logic) run in `PreUpdate`/`Update`/`PostUpdate`. They write `Transform`, `Mesh`, `Camera`, `Light` components on the **live** side of the ecs storage.
- Render systems run in `Update`/`PostUpdate` (post-R6, can also pipeline as `Extract`-equivalent). The scheduler infers from each render system's `access_list` that its component reads should route to the **snapshot** side (the double-buffered back copy).
- At phase boundaries the scheduler atomically rotates the snapshot index. Sim N+1 writes the new live side while render N reads the new snapshot side. No lock, no copy step, no separate "frame packet" object.
- Inference is automatic: any component touched by a render-phase system gets `KE_COMPONENT_DOUBLE_BUFFERED` set on registration. Components only sim reads/writes stay single-buffered (zero overhead). Escape hatches `[NoDoubleBuffer]` / `[ForceDoubleBuffer]` exist for the rare exception.
- The L5 helpers don't care which side they're reading. They consume entity + cid via `ke_system_ctx_get` / `_get_mut`; the snapshot routing happens one layer below in the ecs vtable.

### 9.4 Pre-R6 transitional state

R4 (already-shipped runtime scheduler, current branch state) does NOT have the snapshot mechanism. Sim and render run serially: PreUpdate → Update → PostUpdate, with render-phase systems running on the same pinned worker but reading live storage. Single-threaded with respect to the sim/render boundary; the scheduler can still parallelize multiple render passes against each other within the same phase if their write sets are disjoint.

This is functionally correct (render reads finalized sim state) but leaves performance on the table — sim cannot start frame N+1 while render is still on frame N. R6 lights up that pipelining by flipping the snapshot bits as described in §9.3, transparently to the render code written under §9.2.

The corollary worth stating explicitly: **frame_packet does not exist in either state**. The LEGACY `*_render_system.cpp` extract-and-write-packet pattern was deleted in C-phase 4 of the runtime arc (`RuntimeArchitectureV2.md` §17.6.1) precisely because the snapshot model makes it redundant. Render passes read components directly; there is no intermediate per-frame snapshot object. The doc this section replaces previously called frame_packet "stable" — that claim is retracted (see §12).

### 9.5 Hot reload + asset upload threading

- **Shader hot reload**: a filesystem watcher (running on a scheduler worker — not its own thread) detects `.slang` changes, kicks Slang compilation on the same pool, invalidates the affected PSO RAM cache entries. Next render frame, the PSO request hits a miss → Mechanism 1 fallback per §6.
- **Asset upload**: `ResourceUploader.enqueue_upload(buffer, data, size)` (§5.3) is called from any thread. The uploader's staging ring buffer is the synchronization point; copies into staging happen on whichever scheduler worker takes the queued task. The render-thread-pinned pass then issues the actual GPU copy command on the encoder.
- **Background PSO compile**: same pool, same submit pattern. The dispatcher does not care which worker compiles the PSO; the result lands in the cache, and the next render frame's PSO lookup finds it.

### 9.6 What game code touches

- Game code touches `Material`, `Mesh`, `Texture` (managed wrappers around opaque handles, refcounted, sim-safe). Setting `meshNode.MeshHandle = ...` writes to `MeshComponent.mesh` in the ecs — that's a sim-side write, picked up next render frame via the snapshot.
- Game code NEVER touches `ke_gpu_device`. The render-module-owned device handle stays inside `KernelEngine.Render.Modern`. Even custom user render passes (registered as game-side modules) declare component access lists and use the L5 helpers, not the device.

---

## 10. Migration plan

Parallel-build, not in-place. Old renderer keeps shipping; V2 is a separate plugin slot.

### Phase G0 — This doc + RuntimeArchitectureV2 lock-in
Discussion, revision, until both sides agree.

### Phase G1 — Slang spike (1-2 sessions)
- Slang compiler in our vcpkg / CMake.
- Pick 1-2 simple shaders (e.g. `fs_basic`), port to `.slang`.
- Add a `compile_shaders.py` path for `.slang` → all backends.
- Currently-shipping renderer (`Render.Bgfx`) gets a `.slang`-sourced shader pair to validate the pipeline e2e. Visual parity check via example 01_window_scene.

### Phase G2 — Extract mid-level abstractions in current code (2-3 sessions)
- Inside `KernelEngine.Render.Bgfx` + `Render.Core`, extract `RenderPassBuilder`, `ComputePassHelper`, `ResourceUploader`, `MaterialBinding`, `CommandRecorder`, `PipelineCache` interfaces. **Backends call them; they call gpu_device.**
- Refactor `core_renderer.cpp` so it has zero direct `gpu_device->` calls outside the abstractions.
- Zero visual change. All examples + Pong + tests stay green.
- **This is the most important refactor** — it turns the future device swap from a 3-month job into a contained one.
- **State at start of G2**: the LEGACY `*_render_system.cpp` extract pipeline is already gone (`RuntimeArchitectureV2.md` §17.6.1 C-phase 4 deleted it). `core_renderer.cpp` no longer has a frame-packet consumer in the middle — it's already a self-contained module that reads ecs components and submits draws. G2's job is purely the L4/L5 abstraction extraction; the integration shape is settled.

### Phase G3 — `ke_gpu_device` promoted to kernel C ABI (1-2 sessions)
- Move `gpu_device.hpp` (current C++ class) to `src/c/kernel/include/kernel_engine/kernel/render/gpu_device.h` as a C vtable struct.
- Existing `BgfxGpuDevice` rewrites its fillers (same code, different syntax).
- All consumers in `Render.Core` already go through L5 abstractions (post-G2), so the surgery is local to the abstractions.

### Phase G4 — `KernelEngine.Render.Modern` plugin shell + wgpu-native backend (2-3 sessions)
- New plugin under `src/cpp/render/modern/` + `src/c/kernel/include/kernel_engine/render/modern/render_modern.h`.
- Bring in wgpu-native via vcpkg.
- Implement `ke_gpu_device` vtable as a wgpu-native wrapper.
- Render a triangle through the full L3 surface. No engine integration yet.

### Phase G5 — Mid-level + render-graph on Modern backend (3-5 sessions)
- Port L5 abstractions to run against `Render.Modern` device. They're already device-agnostic from G2.
- Port render-graph passes to use L5 (already device-agnostic from G2).
- Now `example_01_window_scene` opts into Modern via DI. Both renderers selectable.

### Phase G6 — PSO Mechanism 1: ubershader + magenta fallback (3-4 sessions)
- `PipelineCache` skeleton (RAM only, no disk yet).
- Build the ubershader: a Slang program parameterized over the common-case feature set (PBR forward + shadow + depth prepass). Compiles into one large PSO at engine init.
- Ubershader compatibility map: given a PSO request, decide whether the ubershader can cover it.
- Magenta placeholder PSO compiled at engine init for the exotic-request path.
- Background compile via worker pool: PSO miss → return fallback PSO + enqueue compile → next frame swap.
- Hot reload via filesystem watch on `.slang` files invalidates RAM cache entries.
- Goal: dev iteration (Pong loop, hot-reload, examples) never stalls regardless of cache state.

### Phase G6.1 — PSO Mechanism 3: disk cache + driver hash (2 sessions)
- Compute `driver_hash` at boot (GPU vendor/device, driver version, OS).
- Cache directory: `<localappdata>/KernelEngine/<game_id>/<engine_ver>/<driver_hash>/`.
- Lazy load: PSO request → RAM miss → disk lookup → device->create_pipeline_from_blob → RAM cache → return.
- Compile success → write bytecode to disk.
- Cache invalidation on driver_hash change.
- Goal: second launch onward, zero compilation in steady state.

### Phase G6.2 — PSO Mechanism 2: build-time manifest (3-4 sessions)
- `ke build manifest` CLI verb (extends existing CLI from B4 / P2).
- Walks all materials referenced in scenes / Project / code.
- Computes cartesian product (material × pass × vertex layout × variant) → PSO keys.
- Emits `build/psos.manifest` (TOML).
- First-launch flow: read manifest, compile every PSO into disk cache, splash UI "Optimizing 750/750".
- Manifest coverage metric: compares manifest entries against PSOs requested by examples → reports missing entries as warnings (these would have been Mechanism 1 fallbacks in release).
- Goal: shippable release builds with zero unexpected stalls.

### Phase G7 — Feature parity sweep (open-ended)
- Port one feature at a time to Modern: PBR materials, shadow mapping, IBL, tone mapping, post-processing chain, etc.
- Each port = (a) port the relevant Slang shader if not done, (b) port the render-graph pass to Modern. Examples validate visually.
- Bgfx renderer untouched during this phase. Anyone hitting a Modern bug rolls back to Bgfx via DI.

### Phase G8 — Cut over default; deprecate Bgfx
- Default DI swap.
- Bgfx renderer stays in tree as alt option (Render.Bgfx becomes "legacy stable" — receives only critical fixes).
- Eventually delete after 3+ months of Modern as default with no regressions.

### Risk gates
- After G1: Slang works. If not, fall back to keeping bgfx `.sc` for engine shaders + only using Slang for user material shaders (smaller benefit, still a win).
- After G2: refactor leaves all examples + tests passing. **Hard gate.** If any regression survives, halt G2 until clean.
- After G4: triangle renders through Modern. **Hard gate.**
- After G5: example_01 visually matches Bgfx. **Hard gate.**

---

## 11. Culling architecture — render-graph passes, not a dedicated pipeline

Culling is **not** a hardcoded pipeline stage. It's a **set of optional render-graph passes** that consume the full extracted entity list and produce filtered lists for downstream draws. Game composes the culling chain that fits its scene. Engine ships the two basic flavors; everything else is opt-in or user-authored.

### 11.1 The flow

```
SIM PHASES (sim-side, no special "extract" — there is none):
    write Transform, Mesh, Material, AABB, lod_group_id, layer_mask
    components onto entities as game state. That's it.

RENDER PHASE (pinned to ke.render worker, reads via snapshot post-R6):
    ┌─ FrustumCullPass          (engine built-in)
    │      access_list: Transform READ, MeshAabb READ, Camera READ;
    │                   VisibleSet WRITE (resource — a flat array
    │                   of visible entity IDs filled per camera)
    │      first impl: CPU SIMD walking the snapshot Transform+AABB
    │                  columns (~5-10 ns / entity)
    │      G7+ impl: compute shader variant for huge scenes
    │
    ├─ OcclusionCullPass        (engine built-in — Hi-Z based)
    │      access_list: VisibleSet READ/WRITE, Hi-Z texture binding
    │                   (from prev frame depth)
    │      compute shader; ~50 µs for ~100K entities on a mid GPU
    │
    ├─ [USER PASSES — opt-in]
    │      PortalCullPass, RoomCullPass, custom LOD selector, ...
    │      User registers between built-ins or replaces them entirely.
    │
    └─ DrawPass(es)             (consume final VisibleSet + read
                                 MeshComponent/MaterialComponent via
                                 snapshot to issue draws)
```

The thing that's gone vs the original draft: **no "publish all entities to frame packet" step**. There is no frame packet. Cull passes read the components they need straight from the ecs snapshot back-buffer (post-R6) or the live storage (pre-R6 transitional). The "full entity list" is a snapshot column iteration, not a per-frame copied list.

### 11.2 Why this matters architecturally

1. **Composable** — simple game registers only `FrustumCullPass`. Open-world game adds `OcclusionCullPass`. Level-based game with line-of-sight tricks (Quake-style PVS, portal culling) adds its own pass between built-ins and Draw. **Engine doesn't pick the combination**; render graph wires whatever's registered.

2. **Hi-Z is shared infrastructure** — the depth pyramid that `OcclusionCullPass` consumes is the same pyramid that TAA, SSAO, SSR consume. Built once at the start of the frame's depth-aware passes; cached for the rest. Pass authoring sees it as a graph dependency, not a special case.

3. **GPU-driven culling is the same architecture, just bigger** — when `[F.RC1]` GPU instancing lands, `OcclusionCullPass` evolves: instead of writing the `VisibleSet` resource as a CPU list, it writes an **indirect draw buffer** in GPU memory that downstream draws consume directly. Same node in the render graph; different output buffer kind. No architectural rework.

4. **Mods/users extend without forking** — same doctrine as everything else: layered abstractions + register, never replace. A game-specific cull strategy ships as another plugin's render-graph pass.

### 11.3 What the engine ships

- **`FrustumCullPass`** — AABB-vs-6-planes, CPU SIMD first impl (~50-100 LoC + helpers). Cheap, debuggable, runs on render thread. Compute variant added in G7+ when actually needed (the CPU one is good up to ~10K visible entities).
- **`OcclusionCullPass`** — Hi-Z + AABB-to-screen reprojection. ~300 LoC + one compute shader. References: Frostbite "Practical Order-Independent Transparency" depth-buffer paper, Ubisoft Anvil GDC slides on Hi-Z occlusion. Both well-documented; we wrap the patterns, not invent them.

### 11.4 What the engine does NOT ship

- **Portal culling, PVS, antiportals, etc.** — game-specific. User implements as their own render-graph pass.
- **Voxel-based occlusion**, **scene-graph cell culling**, **destructible-aware culling** — same. Plug, don't beg the engine.
- **Per-light culling** — already covered by clustered forward shading (`[F.RC3]` shipped). Different concern from per-mesh culling discussed here.

---

## 12. What V2 explicitly does NOT change (non-goals)

- **`ke_render` vtable** stays mostly as-is at L7 for the imperative `submit_mesh`/`submit_skybox` slots game code calls (legacy entry points retained for compatibility). Modern renderer implements the same vtable so swap is transparent. The modern preferred path, however, is "set the component, let the render module's passes pick it up" — `submit_mesh` becomes an escape hatch, not the main road.
- **`Material` / `Mesh` / `Texture` C# wrappers** stay. Refcounting, handle types, etc. preserved.
- **Render graph contract** — already shipped, used as-is.
- ~~Frame packet contract — unchanged. The boundary is stable.~~ → **Retracted**. Frame packet was the boundary in the original V2 draft; the runtime architecture work (`RuntimeArchitectureV2.md` §16, §17.6.1 C-phase 4) replaced it with per-component snapshot before this doc reached "Accepted". Modern renderer never reads or writes a frame packet object; it reads components via `ke_system_ctx` and the snapshot routing happens inside the ecs vtable.
- **bgfx renderer** stays alive until full V2 parity. Not a single line touched during G3-G6.
- **Component vocabulary** — Modern renderer does NOT redeclare `Camera`/`Light`/`Mesh` components. It reads the framework's definitions from `kernel/framework/components.h`, exactly like the Bgfx renderer does today. A different framework on top of this kernel can declare a different vocabulary; the Modern renderer's job is to read whatever the registered framework decides to ship.

---

## 13. Open questions (lock during the relevant phase)

1. **wgpu-native vs direct Vulkan** for the first Modern backend impl. Recommendation: wgpu-native; revisit if a capability is missing. Decision deadline: start of G4.
2. **Disk PSO cache location**: per-user (`~/.cache/kernelengine/`) or per-project (`./build/cache/`)? Probably per-user keyed by project + engine version. Lock during G6.
3. **PSO cache cross-machine portability**: PSOs include driver-specific compiled bytecode. Cross-machine cache = no. Per-machine cache. Document this so shipped games understand they'll PSO-warm on first launch per player.
4. **Async compute support**: the device exposes a compute queue separate from graphics. Where does the engine actually use it? Probably nowhere in M1; G7+ for GPU-driven culling, light culling, etc. Don't design for it yet — the API allows it (multiple Queue handles), impl can ignore until needed.
5. **Bindless support**: WebGPU spec is conservative here. Vulkan / D3D12 allow large descriptor sets that effectively bindless. The `ke_gpu_bind_group_layout` can express this on capable backends; bindless-aware shaders detect via capability flag. Lock the API shape during G3.
6. **Variable-rate shading, mesh shaders, RT pipelines**: each requires extra vtable entries (`create_mesh_pipeline`, `trace_rays`, etc.). Capability-gated; missing capability returns invalid handle + sets an error. Define API per technique as we implement.
7. **Slang language version pinning**: shader language evolves. Pin a Slang version in vcpkg, bump deliberately. Document in `docs/Development/Versions.md` or similar.

---

## 14. Alternatives considered

- **Keep bgfx, refactor in place** — rejected. bgfx's high-level API actively hides the control we need; staying means continuing to lie that the engine uses Vulkan when it uses OpenGL-shaped Vulkan. Refactoring in place fights every example simultaneously.
- **Switch to The Forge** — was a candidate when we needed "AAA capabilities now". With Modern V2 + wgpu-native, **The Forge is no longer on the table**. wgpu covers PC (Vulkan/D3D12/Metal) + mobile (Vulkan/Metal) + web (WebGPU); the only thing it lacks today is RT pipelines, which we don't need until M5+. When the engine outgrows wgpu (real consumer demands hardware RT, mesh shaders, or capability wgpu doesn't expose), the layered architecture from §2 lets us write our **own** second backend instead of importing an external library — by then the engine is mature, the contracts are stable, and the trade-off of bringing in someone else's render abstraction (Apache 2.0 attribution, larger binary, opinionated state model) costs more than it saves. **The Forge card retired**. Long-term backend evolution stays in-house.
- **Roll own Vulkan-direct from day one** — too much work. The mid-level abstractions deserve to land first; the backend below them is interchangeable.
- **Sokol (single-file C library) as the device** — too constrained, no compute support on legacy backends, no RT path. Rejected.

---

## 15. Status & next actions

- [x] User reviewed this doc + `RuntimeArchitectureV2.md` together (paired during the 2026-06 V1 merge arc).
- [x] §9 + §11 + §12 reconciled with `RuntimeArchitectureV2.md` §16 (per-component snapshot) and §17.6 (LEGACY render systems deleted in C-phase 4, frame_packet abandoned). The boundary contract is component snapshot, not frame packet.
- [ ] Lock §4 C ABI signatures. Anything ambiguous gets pinned before G1.
- [ ] **Sequence start with G1 (Slang spike)** — independent of the runtime work, can run in parallel with the rest of the V1 merge arc.
- [ ] G2 (extract mid-level abstractions in current code) is the most valuable single piece of work in this doc. Do it even if V2 never ships — it pays back the next time we touch the renderer for any reason.

**This doc is the contract.** When G3 ships, every word in §3 + §4 + §5 should match the code or this doc gets revised. §9 + §11 + §12 are already aligned with the runtime contracts that landed in branch `feat/runtime-v2`; the Modern renderer slots in as a runtime Module on that foundation, no extra glue layer.
