namespace KernelEngine.Render.Webgpu.Native;

/// <summary>
/// Opaque marker for the native <c>ke_gpu_render_pipeline_params</c> struct. It is only
/// ever referenced as a pointer parameter to <c>ke_render_core.get_or_create_pipeline</c>,
/// which no C# call-site invokes (every pass that needs a PSO is a Zig render-pass plugin).
/// Hand-written (excluded from GpuDevice.rsp) so regeneration never re-expands its full
/// field layout — and the many enum/struct types it alone would drag back in — for a
/// slot C# never calls.
/// </summary>
public struct ke_gpu_render_pipeline_params
{
}
