namespace KernelEngine.Render.Webgpu.Native;

/// <summary>
/// Opaque marker for the native <c>ke_gpu_device</c> vtable. C# never dereferences its
/// method-pointer slots — it only holds the pointer (from <c>gpu_device_webgpu_create</c>)
/// and passes it opaquely into <c>render_module_create</c>; every real call against this
/// vtable happens inside the Zig render-pass plugins. Hand-written (excluded from
/// GpuDevice.rsp) instead of generated, so regeneration never re-expands it into the
/// full ~37-method struct layout only Zig needs.
/// </summary>
public struct ke_gpu_device
{
}
