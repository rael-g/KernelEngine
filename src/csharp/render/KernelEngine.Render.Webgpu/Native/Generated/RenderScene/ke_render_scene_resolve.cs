using KernelEngine.Asset.Native;
using KernelEngine.Common.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_scene_resolve
{
    public void* handle;

    [NativeTypeName("const ke_render_scene_component_ids *(*)(struct ke_render_scene_resolve *)")]
    public delegate* unmanaged[Cdecl]<ke_render_scene_resolve*, ke_render_scene_component_ids*> component_ids;
}
