using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_tonemap_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* device;

    [NativeTypeName("ke_component_id")]
    public uint frame_cid;
}
