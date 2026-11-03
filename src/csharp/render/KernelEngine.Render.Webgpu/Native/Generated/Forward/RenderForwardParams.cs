using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct RenderForwardParams
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* Runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* Service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* Device;

    public bool IblEnabled;

    [NativeTypeName("ke_render_scene_resolve *")]
    public KernelEngine.Render.Native.ke_render_scene_resolve* Scene;

    [NativeTypeName("ke_render_frame *")]
    public KernelEngine.Render.Native.ke_render_frame* Frame;

    [NativeTypeName("const char *")]
    public sbyte* Shadow;

    [NativeTypeName("const char *")]
    public sbyte* Clusters;
}
