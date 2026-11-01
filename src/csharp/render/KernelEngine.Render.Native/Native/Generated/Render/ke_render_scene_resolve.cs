using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_scene_resolve
{
    public void* handle;

    [NativeTypeName("const ke_render_scene_component_ids *(*)(struct ke_render_scene_resolve *)")]
    public delegate* unmanaged[Cdecl]<ke_render_scene_resolve*, global::KernelEngine.Render.RenderSceneComponentIds*> component_ids;
}
