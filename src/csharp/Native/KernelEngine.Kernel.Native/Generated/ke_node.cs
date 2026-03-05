namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_node
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, void> destroy;

    [NativeTypeName("const char *(*)(struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, sbyte*> get_name;

    [NativeTypeName("ke_result (*)(struct ke_node *, ke_transform *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_transform*, ke_result> get_local_transform;

    [NativeTypeName("ke_result (*)(struct ke_node *, const ke_transform *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_transform*, ke_result> set_local_transform;

    [NativeTypeName("ke_result (*)(struct ke_node *, ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_mat4*, ke_result> get_world_matrix;

    [NativeTypeName("ke_result (*)(struct ke_node *, struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_node*, ke_result> add_child;

    [NativeTypeName("ke_result (*)(struct ke_node *, struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_node*, ke_result> remove_child;

    [NativeTypeName("struct ke_node *(*)(struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_node*> get_parent;

    [NativeTypeName("struct ke_node *(*)(struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_node*> get_first_child;

    [NativeTypeName("struct ke_node *(*)(struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_node*> get_next_sibling;

    [NativeTypeName("ke_result (*)(struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ke_result> on_start;

    [NativeTypeName("ke_result (*)(struct ke_node *, float)")]
    public delegate* unmanaged[Cdecl]<ke_node*, float, ke_result> on_update;

    [NativeTypeName("ke_entity (*)(struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ulong> get_entity;

    [NativeTypeName("void (*)(struct ke_node *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_node*, ulong, void> set_entity;
}
