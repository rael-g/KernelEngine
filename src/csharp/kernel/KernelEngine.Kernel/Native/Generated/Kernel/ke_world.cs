namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_world
{
    public void* handle;

    [NativeTypeName("ke_ecs *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_ecs*> ecs;

    [NativeTypeName("ke_runtime *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_runtime*> runtime;

    [NativeTypeName("struct ke_scene_tree *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_scene_tree*> scene_tree;

    [NativeTypeName("ke_result (*)(struct ke_world *, ke_component_id, ke_component_apply_fn, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, delegate* unmanaged[Cdecl]<void*, ke_variant_table_entry*, uint, void>, ke_error**, ke_result> register_component_apply;

    [NativeTypeName("ke_component_apply_fn (*)(struct ke_world *, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, delegate* unmanaged[Cdecl]<void*, ke_variant_table_entry*, uint, void>> get_component_apply;

    [NativeTypeName("void (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, void> destroy;
}

public partial struct ke_world
{
}
