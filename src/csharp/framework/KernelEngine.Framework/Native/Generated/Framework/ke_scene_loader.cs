using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_loader
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_scene_loader *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, sbyte*, ke_error**, bool> load;

    [NativeTypeName("bool (*)(struct ke_scene_loader *, ke_script_factory_func, void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, delegate* unmanaged[Cdecl]<void*, ulong, sbyte*, ke_error**, bool>, void*, ke_error**, bool> register_script_factory;
}
