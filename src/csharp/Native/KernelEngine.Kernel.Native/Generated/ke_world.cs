namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_world
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, void> destroy;

    [NativeTypeName("struct ke_scene *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_scene*> get_scene;

    [NativeTypeName("struct ke_ecs_registry *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_ecs_registry*> get_registry;

    [NativeTypeName("ke_result (*)(struct ke_world *, const struct ke_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_frame*, ke_result> update;

    public partial struct ke_ecs_registry
    {
    }
}
