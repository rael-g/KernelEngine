namespace KernelEngine.Kernel.Native;

public partial struct ke_world
{
}

public unsafe partial struct ke_world
{
    public void* handle;

    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_ecs_registry *")]
    public ke_ecs_registry* registry;

    public void* internal_data;

    [NativeTypeName("void (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_world *, const struct ke_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_frame*, ke_result> update;

    [NativeTypeName("struct ke_ecs_registry *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_ecs_registry*> get_registry;

    [NativeTypeName("ke_result (*)(struct ke_world *, const ke_system_desc *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_system_desc*, ke_result> add_system;

    [NativeTypeName("uint32_t (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint> transform_id;

    [NativeTypeName("uint32_t (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint> hierarchy_id;

    [NativeTypeName("uint32_t (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint> name_id;

    [NativeTypeName("uint32_t (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint> script_id;

    [NativeTypeName("struct ke_task_scheduler *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_task_scheduler*> get_task_scheduler;

}
