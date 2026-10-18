using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_tonemap_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;

    [NativeTypeName("ke_component_id")]
    public uint frame_cid;
}
