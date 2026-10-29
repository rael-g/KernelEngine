using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_component_set
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_scene_component_set *, const ke_component_params *, ke_component_apply_fn)")]
    public delegate* unmanaged[Cdecl]<ke_scene_component_set*, KernelEngine.Ecs.Native.ke_component_params*, delegate* unmanaged[Cdecl]<void*, void*, KernelEngine.Ecs.Native.ke_variant_table_entry*, uint, KernelEngine.Result.Native.ke_result>, KernelEngine.Result.Native.ke_result> add;

    [NativeTypeName("ke_result (*)(struct ke_scene_component_set *, ke_ecs *, ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_component_set*, KernelEngine.Ecs.Native.ke_ecs*, ke_world*, KernelEngine.Result.Native.ke_result> register_into;
}
