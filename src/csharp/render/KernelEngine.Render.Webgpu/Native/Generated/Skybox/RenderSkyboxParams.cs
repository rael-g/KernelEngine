using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct RenderSkyboxParams
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* Runtime;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* Service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* Device;

    [NativeTypeName("ke_render_camera *")]
    public KernelEngine.Render.Native.ke_render_camera* Camera;

    [NativeTypeName("ke_render_scene_resolve *")]
    public KernelEngine.Render.Native.ke_render_scene_resolve* Scene;

    [NativeTypeName("ke_render_frame *")]
    public KernelEngine.Render.Native.ke_render_frame* Frame;
}
