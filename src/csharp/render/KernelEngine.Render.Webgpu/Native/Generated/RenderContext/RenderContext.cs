using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Ecs.Native;
using KernelEngine.Render.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct RenderContext
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* Runtime;

    [NativeTypeName("ke_ecs *")]
    public KernelEngine.Ecs.Native.ke_ecs* Ecs;

    [NativeTypeName("ke_render_service *")]
    public KernelEngine.Render.Native.ke_render_service* Service;

    [NativeTypeName("ke_gpu_device *")]
    public KernelEngine.Render.Native.ke_gpu_device* Device;

    [NativeTypeName("ke_view_space *")]
    public KernelEngine.View.Native.ke_view_space* ViewSpace;

    [NativeTypeName("ke_render_camera *")]
    public KernelEngine.Render.Native.ke_render_camera* Camera;

    [NativeTypeName("ke_render_scene_resolve *")]
    public KernelEngine.Render.Native.ke_render_scene_resolve* Scene;

    [NativeTypeName("ke_render_frame *")]
    public KernelEngine.Render.Native.ke_render_frame* Frame;
}
