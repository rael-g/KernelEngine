namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_scene_loader
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, sbyte*, ke_result> load;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, ke_script_factory_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, delegate* unmanaged[Cdecl]<void*, ulong, sbyte*, ke_result>, void*, ke_result> register_script_factory;

    [NativeTypeName("void (*)(struct ke_scene_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, void> destroy;
}
