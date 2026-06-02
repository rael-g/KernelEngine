namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_loader
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, sbyte*, ke_result> load;

    [NativeTypeName("void (*)(struct ke_scene_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, void> destroy;
}
