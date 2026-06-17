namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_scene_tree
{
    public void* handle;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong> root;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, const char *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, ulong, ulong> create_node;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *, ke_entity, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, ke_error**, ke_result> destroy_node;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> destroy_all;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, ulong> find_node;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> propagate_transforms;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> destroy;
}

public partial struct ke_scene_tree
{
}
