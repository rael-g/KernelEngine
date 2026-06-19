using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_loader
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, sbyte*, ke_error**, ke_result> load;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, ke_script_factory_func, void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, delegate* unmanaged[Cdecl]<void*, ulong, sbyte*, ke_result>, void*, ke_error**, ke_result> register_script_factory;
}
