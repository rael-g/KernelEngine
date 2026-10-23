using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_component_set
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_scene_component_set *, ke_ecs *, ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_component_set*, KernelEngine.Ecs.Native.ke_ecs*, ke_world*, KernelEngine.Result.Native.ke_result> register_into;
}
