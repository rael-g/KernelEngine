namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_ecs
{
    public void* handle;

    [NativeTypeName("ke_entity (*)(struct ke_ecs *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong> entity_create;

    [NativeTypeName("void (*)(struct ke_ecs *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, void> entity_destroy;

    [NativeTypeName("ke_component_id (*)(struct ke_ecs *, const char *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, sbyte*, nuint, uint> component_register;

    [NativeTypeName("void *(*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, uint, void*> component_add;

    [NativeTypeName("void (*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, uint, void> component_remove;

    [NativeTypeName("void *(*)(struct ke_ecs *, ke_entity, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, ulong, uint, void*> component_get;

    [NativeTypeName("void (*)(struct ke_ecs *, ke_component_id, ke_entity **, void **, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, uint, ulong**, void**, nuint*, void> query;

    [NativeTypeName("void (*)(struct ke_ecs *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, void> destroy;
}
