using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_component_set
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_scene_component_set *, ke_ecs *, ke_world *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_component_set*, KernelEngine.Ecs.Native.ke_ecs*, ke_world*, KernelEngine.Common.Native.ke_error**, bool> register_into;
}
