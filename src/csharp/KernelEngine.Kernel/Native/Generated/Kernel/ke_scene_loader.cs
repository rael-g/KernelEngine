namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_scene_loader
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, sbyte*, int> load;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, ke_script_factory_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, delegate* unmanaged[Cdecl]<void*, ulong, sbyte*, int>, void*, int> register_script_factory;

    [NativeTypeName("void (*)(struct ke_scene_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, void> destroy;
}
