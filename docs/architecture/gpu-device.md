# What does the GPU device contract promise, and what does the WebGPU backend do with it?

This is a map: the parts of the GPU layer, what each receives and what it hands on. The
contract is in the headers under `src/c/render/kernel_engine/render/gpu/`; how a part works
inside is on the generated page of its file.

## The parts

| part | contract | plugin | receives | hands on |
|---|---|---|---|---|
| device | `ke_gpu_device` | webgpu | optionally a `ke_scheduler` and creation flags (`ke_gpu_device_webgpu_params`) | buffers, textures, views, samplers, shader modules, pipelines, bind groups |
| recording | `ke_gpu_command_encoder`, `ke_gpu_render_pass`, `ke_gpu_compute_pass`, `ke_gpu_command_buffer` | webgpu | the device | command buffers, for `queue_submit` |
| window target | `ke_gpu_render_target` | webgpu | the device, a `ke_window` | the surface texture of a frame, and its presentation |
| texture target | `ke_gpu_render_target` | texture_target | the device, a texture | that texture as the frame |
| capture target | `ke_gpu_render_target` | renderdoc_target | another `ke_gpu_render_target` | the same frames, bracketed by a RenderDoc capture |

The render service is the device's consumer in the engine; it is described in
[render.md](render.md).

## What ties the parts together

**Everything is a 64-bit handle.** Resources are `uint64_t` typedefs and
`KE_GPU_INVALID_HANDLE` is the failure value. A call that can fail with a message takes a
`ke_error`; the rest return the invalid handle or nothing.

**Recording is a second set of vtables.** The device makes a command encoder; the encoder
begins render and compute passes and finishes into a command buffer; `queue_submit` takes the
buffers. The device owns the wrappers it hands out and the caller ends or destroys each one.

**The device describes itself.** `get_capabilities`, `shader_language` and
`get_ndc_convention` (`ke_ndc_convention`) are how a consumer learns the limits, the shader
language it must load and the clip space it must build projections for.

**A target is a frame source.** `acquire` returns the view a frame draws into and `present`
ends the frame. A target may wrap another one, which is how a capture target sits on a window
target.

**Pipelines can compile off the caller's thread.** `create_render_pipeline_async` reports
through a callback and `flush_pipeline_compiles` waits for all of them; the policy built on
them is in [pipeline-cache.md](pipeline-cache.md).

**Events are pumped by the owner.** `queue_poll` delivers the callbacks of finished work
(`create_render_pipeline_async`, `map_buffer_read`).

## What the parts agree on without a contract

- The window target accepts only a device made by the webgpu plugin, and refuses any other.
- Error types: the contract declares `KE_ERROR_GPU_SHADER_COMPILATION` and
  `KE_ERROR_GPU_RESOURCE_CREATION`; the webgpu plugin reports their children
  `KE_ERROR_WGPU_SHADER_COMPILATION` and `KE_ERROR_WGPU_RESOURCE_CREATION`.
- Labels reach a capture tool only when the device was created with `debug_labels` set in
  `ke_gpu_device_webgpu_params`.
- Texture-to-buffer and buffer-to-texture copies require a row pitch that is a multiple of
  the alignment `get_capabilities` reports in `copy_bytes_per_row_alignment`.
