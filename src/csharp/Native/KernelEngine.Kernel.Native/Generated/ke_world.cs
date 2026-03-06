namespace KernelEngine.Kernel.Native;

public partial struct ke_world
{
}

public unsafe partial struct ke_world
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, void> destroy;

    [NativeTypeName("struct ke_ecs_registry *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_ecs_registry*> get_registry;

    [NativeTypeName("ke_result (*)(struct ke_world *, const struct ke_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_frame*, ke_result> update;

    [NativeTypeName("ke_entity (*)(struct ke_world *, const char *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_world*, sbyte*, ulong, ulong> create_node;

    [NativeTypeName("ke_result (*)(struct ke_world *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ulong, ke_result> destroy_node;

    [NativeTypeName("ke_entity (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ulong> get_root;

    [NativeTypeName("ke_component_id (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint> transform_id;

    [NativeTypeName("ke_component_id (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint> hierarchy_id;

    [NativeTypeName("ke_component_id (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint> name_id;

    [NativeTypeName("ke_component_id (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint> script_id;

    [NativeTypeName("ke_result (*)(struct ke_world *, const ke_system *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_system*, ke_result> add_system;
}
