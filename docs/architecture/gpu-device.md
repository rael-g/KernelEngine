# What does the GPU device contract promise, and what does the WebGPU backend do with it?

The GPU device is the lowest rendering contract: buffers, textures, pipelines, command recording and
presentation, and nothing about frames, passes or materials. The render service builds on it
([render.md](render.md)). The contract is `src/c/render/kernel_engine/render/gpu/gpu_device.h` and
`gpu_commands.h`; the one implementation is the WebGPU plugin `ke_gpu_device_webgpu`
(`src/zig/render/webgpu/src/gpu_device_webgpu.zig`, `build.zig:280`).

## What the contract is

**Handles are 64-bit integers.** Buffers, textures, views, samplers, shader modules, pipelines, bind
groups, layouts, queues and fences are `uint64_t` typedefs, and `KE_GPU_INVALID_HANDLE` is
`UINT64_MAX` (`gpu_device.h:15-24`, `gpu_enums.h:239`). The WebGPU backend stores the underlying
pointer in the integer (`@intFromPtr`, e.g. `gpu_device_webgpu.zig:1194-1207`).

**The device is a vtable** (`ke_gpu_device`, `gpu_device.h:265-356`), obtained from a factory that
returns an owner wrapper `{ref, destroy}` (`gpu_device.h:358-362`). Its slots fall into groups:

| group | slots |
|---|---|
| queue | `get_default_queue`, `queue_submit`, `queue_present`, `queue_wait_idle` |
| fences | `create_fence`, `queue_signal_fence`, `wait_fence`, `get_fence_value`, `destroy_fence` |
| resources | `create_*` and `destroy_*` for buffer, texture, texture view, sampler, shader module, pipeline, bind group layout, bind group; `write_buffer`; `map_buffer`, `map_buffer_write`, `unmap_buffer` |
| recording | `create_command_encoder`, then everything in `gpu_commands.h` |
| queries | `get_capabilities`, `shader_language`, `get_ndc_convention`, `query_extension` |
| pipelines | `create_render_pipeline`, `create_compute_pipeline`, `create_render_pipeline_async`, `flush_pipeline_compiles` |

`shader_language`, `get_ndc_convention`, `create_render_pipeline_async` and `flush_pipeline_compiles`
are the last four slots of the struct (`gpu_device.h:331-355`).

**Recording is a second set of vtables** (`gpu_commands.h`). An encoder begins a render pass or a
compute pass and records copies and barriers; `finish` yields a command buffer that `queue_submit`
takes. A render pass has pipeline, bind group, vertex and index buffer, viewport, scissor, `draw`,
`draw_indexed` and `draw_indirect` (`gpu_commands.h:11-36`). A compute pass has pipeline, bind group,
`dispatch` and `dispatch_indirect` (`gpu_commands.h:38-52`). None of the recording slots returns an
error.

**What can report a failure.** `create_buffer`, `create_shader_module`, `create_bind_group` and
`wait_fence` take `ke_error **out_error` (`gpu_device.h:278-279`, `:283-304`). The rest return
`KE_GPU_INVALID_HANDLE` or nothing. Two error types belong to the contract:
`KE_ERROR_GPU_SHADER_COMPILATION` and `KE_ERROR_GPU_RESOURCE_CREATION`, both children of
`KE_ERROR_INVALID_ARGUMENT` (declared at `gpu_device.h:34`, `:41`; defined with their parent at
`gpu_device_webgpu.zig:715-726`).

**What the device tells a caller about itself.**

- `get_capabilities` fills `ke_gpu_capabilities`: texture, bind-group, vertex, buffer and compute
  limits plus three feature flags (`gpu_enums.h:222-237`).
- `shader_language` names the language `create_shader_module` accepts, which is how the render
  service chooses a file extension to load (`shader_loader.zig:9-17`, `:35`).
- `get_ndc_convention` is the clip space the device expects ([view-space.md](view-space.md#what-the-device-reports)).
- `query_extension(name)` returns a typed extension vtable or null. One extension is defined,
  `ke_gpu_surface_ext` (`gpu_surface_ext.h`): acquire the current swapchain view, reconfigure after a
  resize, report the current size. It exists only when the device was created with a window. The render
  service looks it up at creation (`render_service.zig:236-240`) and passes lookups through to its passes
  as `ke_render_pass_ctx::query_ext` (`pass_recording.zig:162-165`).

## Storage, compute and indirect

The contract carries them as ordinary vocabulary rather than an extension: `KE_GPU_BUFFER_USAGE_STORAGE`
and `_INDIRECT`, `KE_GPU_TEXTURE_USAGE_STORAGE` (`gpu_enums.h:57`, `:69-70`), the binding types
`STORAGE_BUFFER` (read-write, compute only), `READONLY_STORAGE_BUFFER` (usable from a fragment stage) and
`STORAGE_TEXTURE` (`gpu_enums.h:200-202`), `create_compute_pipeline`, and the compute and indirect
commands above. The cluster light cull uses storage buffers and a compute dispatch
(`cluster_module.zig:224-230`, `:348-357`); no pass in the tree uses `dispatch_indirect` or
`draw_indirect`.

## What the WebGPU backend does

### Creation

`ke_gpu_device_webgpu_create(params, out_error)` (`gpu_device_webgpu.zig:418`; header
`gpu_device_webgpu_create.h`) takes an optional window and an optional scheduler. Creating the instance,
adapter (high-performance preference) and device is where it can fail, with the error text set on
`out_error` (`gpu_device_webgpu.zig:282-352`, `:418-449`). With a window it creates a surface, prefers
`BGRA8Unorm` or `RGBA8Unorm` from the surface's formats and falls back to the first one offered, and
configures it with `Fifo` presentation (`:334-372`). `shader_language` answers WGSL, and
`get_ndc_convention` answers `z_zero_to_one`, no y flip, left-handed (`:705-711`).

### Resources

- **Buffers, shader modules and bind groups** are created inside a validation error scope that is polled before
  returning; a captured message becomes `KE_ERROR_WGPU_RESOURCE_CREATION` or
  `KE_ERROR_WGPU_SHADER_COMPILATION` (children of the contract's two types) and the call returns the
  invalid handle (`:575-608`, `:756-800`, `:1187`). A buffer created with `initial_data` gains copy-destination
  usage and is filled through the queue.
- **Shader modules** accept SPIR-V when the first word is the SPIR-V magic number and WGSL otherwise
  (`:756-780`).
- **Bind group layouts** map each binding type to a WebGPU entry. A `TEXTURE` is a filterable float
  texture, 2D or cube; a `DEPTH_TEXTURE` is an unfilterable float texture; a `STORAGE_TEXTURE` is fixed
  to write-only `RGBA8Unorm` 2D (`:1080-1136`). Bind groups take at most 32 entries (`:1138-1141`).
- **Mapping.** `map_buffer` and `map_buffer_write` return the mapped range of a buffer and
  `unmap_buffer` unmaps it (`:1412-1420`); they serve a buffer created `mapped_at_creation`.
- **Queue.** `queue_submit` forwards at most 64 command buffers per call (`:489-500`). `queue_present`
  reaps finished compile tasks, presents and releases the acquired surface texture (`:517-527`).

### Pipelines compile off the caller's thread

`create_render_pipeline` compiles on the calling thread. `create_render_pipeline_async` does not call a
WebGPU asynchronous entry point; it adds a reference to each shader module, dispatches a job to the
scheduler passed at creation, and the job calls the synchronous `wgpuDeviceCreateRenderPipeline` and
invokes the callback from its worker (`gpu_device_webgpu.zig:986-1035`). Up to
`MAX_PENDING_COMPILES` = 64 jobs are tracked; with no scheduler, or with 64 already tracked, the
compile runs synchronously and the callback fires before the call returns. `flush_pipeline_compiles` waits on every
tracked job (`:1037-1045`). What the cache built on top of this does is in
[pipeline-cache.md](pipeline-cache.md).

### What the backend does not implement

These slots are declared by the contract and are empty or return a sentinel in the WebGPU backend:

- fences: `create_fence` returns the invalid handle, signal and destroy do nothing, `get_fence_value`
  returns 0, and `wait_fence` fails with "timeline fences not implemented" (`:533-540`);
- `pipeline_barrier` and `copy_buffer_to_texture` do nothing (`:1351`, `:1357`);
- `get_capabilities` sets the numeric limits and leaves `supports_bindless`, `supports_mesh_shaders`
  and `supports_ray_tracing` at zero (`:1422-1439`).
