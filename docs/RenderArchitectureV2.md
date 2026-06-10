# Render Architecture V2 — utopian renderer layered on a WebGPU-style core

**Status**: Draft for discussion. No production code lands until this doc reaches "Accepted".
**Audience**: Engine maintainer + future render plugin authors + game devs writing custom shaders/passes.
**Companion doc**: [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md) — defines `ke_runtime`, the scheduler that drives this renderer.

---

## 1. Purpose

The current renderer (`KernelEngine.Render.Bgfx` + `Render.Core`) is **functional and shipping** but has structural problems that will only get worse as we add modern techniques:

1. **`GpuDevice` API is OpenGL/DX11-era stateful** — `SetState` / `SetUniform` / `Submit` per draw. The control bgfx gives us over Vulkan memory + barriers is *literally not used* because the abstraction above it pretends GL exists.
2. **Hundreds of direct `gpu_device->` calls scattered across `core_renderer.cpp`** — any change to the device API breaks 500 sites at once. Swapping the device is a 3-month project.
3. **No PSO management** — bgfx hides pipeline state objects entirely. When we move to a backend that exposes them (WebGPU-style), we'll either copy Godot's mistake (synchronous compile on first use → "Compiling Shaders" screen) or design it right. We need to design it right *now*, before the problem exists.
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

## 6. PSO architecture — async compile with placeholder (avoids "Compiling Shaders" screen)

The user identified this correctly as a Godot mistake to avoid. Our design:

### 6.1 Compile flow

```
material.request_pipeline(state_key)
        ↓
PipelineCache.lookup(state_key)
        ↓
   ┌─── hit ───→ return cached ke_gpu_pipeline
   │
   └─── miss ──→ enqueue compile job to worker
                 return PLACEHOLDER pipeline (default magenta material,
                       depth-correct, no specialization)
                 next-frame poll: if compile finished, swap to real

Worker thread:
    Slang reflection → emit backend bytecode → device->create_render_pipeline()
    → store in cache (RAM + disk persistent SQLite)
    → fire ready signal
```

### 6.2 What's cached

`state_key` = `hash(shader_module_id, vertex_layout, blend_state, depth_state, render_target_formats, primitive_topology, sample_count)`. Everything that influences PSO compilation.

Two cache tiers:
- **RAM**: lifetime of process. `unordered_map<uint64_t, ke_gpu_pipeline>`.
- **Disk**: persisted across runs. Stored as backend-bytecode blobs in a SQLite DB or per-PSO files under `~/.cache/kernelengine/pso/<engine_version>/`. On startup, RAM cache populated lazily from disk.

### 6.3 Placeholder pipeline

A single global PSO compiled at engine init: vertex shader passes positions through, fragment shader outputs `vec4(1, 0, 1, 1)` (magenta), depth-tested correctly. Renders the geometry in a visually-distinct way without crashing. Game runs at full speed; missing materials appear pink for milliseconds until real PSO arrives.

This is **the** trade-off the user wanted: the player sees a brief pink flash instead of a 30-second freeze. Players forgive flashes. Players uninstall over freezes.

### 6.4 Pre-warming (release builds)

For shipped games, the game author can pre-warm the disk cache at install time or first launch:
- The game declares "required PSOs" via a manifest (or we collect them during a dev "PSO trace" mode)
- On first launch, a background job compiles all of them before the title screen
- Subsequent launches read from disk → zero compile overhead, zero placeholder visible

This is how UE5 / Unreal Engine handle the same problem in shipped titles.

### 6.5 Hot reload

When a `.slang` file changes on disk (dev mode), the PSO cache invalidates every entry referencing that shader module → next request triggers recompile. Game-running shader edits work transparently. See `[HOT-RELOAD]` parking-lot card.

---

## 7. Render graph (already shipped) — recap & integration

The render graph (`src/c/kernel/include/kernel_engine/kernel/render/render_graph.h` + impl) **stays as-is**, sitting at L6. Game code or feature modules declare passes; the graph resolves attachment dependencies, picks execution order, inserts barriers.

The change V2 brings: each render-graph pass is built using the **L5 mid-level helpers** instead of direct device calls. Today, render-graph passes call into `core_renderer.cpp` which calls into `gpu_device->`. After V2, render-graph passes use `RenderPassBuilder` / `ComputePassHelper`, never seeing the device.

No render-graph API change. Pure internal refactor of pass implementations.

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

`KernelEngine.Render.Modern` is a **Module** in the V2 runtime sense (see [`RuntimeArchitectureV2.md`](RuntimeArchitectureV2.md)):

- Registers components: `MeshComponent`, `MaterialComponent`, `CameraComponent`, `LightComponent`, etc. (likely sharing definitions with current `KernelEngine.Render.Bgfx` module).
- Registers systems: `MeshRenderSystem`, `ShadowExtractSystem`, etc. — all in `KE_PHASE_EXTRACT`. They read sim state, write the `FramePacket` resource.
- Owns the **render thread** internally. When the runtime fires the post-Extract signal, the render-thread side wakes, calls the L5/L6 stack, and submits.
- Worker-thread work (asset upload, PSO compile, shader hot reload) goes through the shared `ke_task_scheduler` pool — same as everything else.

There is **no** sim-thread call into `ke_gpu_device`. Game code touches `Material`, `Mesh`, `Texture` (engine wrappers around handles, refcounted, sim-safe). Render thread touches the device. The boundary is the FramePacket.

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

### Phase G6 — PSO cache + async placeholder (2-3 sessions)
- `PipelineCache` with placeholder behavior shipped.
- Disk persistence (SQLite or per-file).
- Hot reload via filesystem watch on `.slang` files.

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

## 11. What V2 explicitly does NOT change (non-goals)

- **`ke_render` vtable** stays mostly as-is at L7. Modern renderer implements the same vtable; game code calling `renderer->submit_mesh()` doesn't care which renderer is wired.
- **`Material` / `Mesh` / `Texture` C# wrappers** stay. Refcounting, handle types, etc. preserved.
- **Render graph contract** — already shipped, used as-is.
- **Frame packet contract** — unchanged. The boundary is stable.
- **bgfx renderer** stays alive until full V2 parity. Not a single line touched during G3-G6.

---

## 12. Open questions (lock during the relevant phase)

1. **wgpu-native vs direct Vulkan** for the first Modern backend impl. Recommendation: wgpu-native; revisit if a capability is missing. Decision deadline: start of G4.
2. **Disk PSO cache location**: per-user (`~/.cache/kernelengine/`) or per-project (`./build/cache/`)? Probably per-user keyed by project + engine version. Lock during G6.
3. **PSO cache cross-machine portability**: PSOs include driver-specific compiled bytecode. Cross-machine cache = no. Per-machine cache. Document this so shipped games understand they'll PSO-warm on first launch per player.
4. **Async compute support**: the device exposes a compute queue separate from graphics. Where does the engine actually use it? Probably nowhere in M1; G7+ for GPU-driven culling, light culling, etc. Don't design for it yet — the API allows it (multiple Queue handles), impl can ignore until needed.
5. **Bindless support**: WebGPU spec is conservative here. Vulkan / D3D12 allow large descriptor sets that effectively bindless. The `ke_gpu_bind_group_layout` can express this on capable backends; bindless-aware shaders detect via capability flag. Lock the API shape during G3.
6. **Variable-rate shading, mesh shaders, RT pipelines**: each requires extra vtable entries (`create_mesh_pipeline`, `trace_rays`, etc.). Capability-gated; missing capability returns invalid handle + sets an error. Define API per technique as we implement.
7. **Slang language version pinning**: shader language evolves. Pin a Slang version in vcpkg, bump deliberately. Document in `docs/Development/Versions.md` or similar.

---

## 13. Alternatives considered

- **Keep bgfx, refactor in place** — rejected. bgfx's high-level API actively hides the control we need; staying means continuing to lie that the engine uses Vulkan when it uses OpenGL-shaped Vulkan. Refactoring in place fights every example simultaneously.
- **Switch to The Forge** — strong choice for AAA capabilities (RT, mesh shaders), but: API not WebGPU-shaped (closer to D3D12), Apache 2.0 with NOTICE attribution requirement, larger binary footprint. **Card already in parking lot as `[F.GPU]` trigger**. Modern V2 with wgpu-native is the friendlier on-ramp; The Forge swap remains a future option *after* V2 lands and we have layered abstractions making any device swap contained.
- **Roll own Vulkan-direct from day one** — too much work. The mid-level abstractions deserve to land first; the backend below them is interchangeable.
- **Sokol (single-file C library) as the device** — too constrained, no compute support on legacy backends, no RT path. Rejected.

---

## 14. Status & next actions

- [ ] User reviews this doc + `RuntimeArchitectureV2.md` together (they're a pair).
- [ ] Lock the §4 C ABI signatures. Anything ambiguous gets pinned before G1.
- [ ] **Sequence start with G1 (Slang spike)** — independent of the runtime work, can run in parallel with R1.
- [ ] G2 (extract mid-level abstractions in current code) is the most valuable single piece of work in this doc. Do it even if V2 never ships — it pays back the next time we touch the renderer for any reason.

**This doc is the contract.** When G3 ships, every word in §3 + §4 + §5 should match the code or this doc gets revised.
