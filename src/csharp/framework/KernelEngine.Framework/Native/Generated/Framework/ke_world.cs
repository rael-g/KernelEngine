using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_world
{
    public void* handle;

    [NativeTypeName("ke_ecs *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, KernelEngine.Ecs.Native.ke_ecs*> ecs;

    [NativeTypeName("ke_runtime *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, KernelEngine.Runtime.Native.ke_runtime*> runtime;

    [NativeTypeName("struct ke_scene_tree *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_scene_tree*> scene_tree;

    [NativeTypeName("bool (*)(struct ke_world *, ke_component_id, const ke_component_field *, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, KernelEngine.Ecs.Native.ke_component_field*, uint, ke_error**, bool> register_component_fields;

    [NativeTypeName("const ke_component_field *(*)(struct ke_world *, ke_component_id, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, uint*, KernelEngine.Ecs.Native.ke_component_field*> get_component_fields;

    [NativeTypeName("bool (*)(struct ke_world *, ke_component_id, ke_component_apply_fn, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, delegate* unmanaged[Cdecl]<void*, KernelEngine.Ecs.Native.ke_variant_table_entry*, uint, bool>, ke_error**, bool> register_component_apply;

    [NativeTypeName("ke_component_apply_fn (*)(struct ke_world *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, delegate* unmanaged[Cdecl]<void*, KernelEngine.Ecs.Native.ke_variant_table_entry*, uint, bool>> get_component_apply;
}
