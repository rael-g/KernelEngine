namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_scene_loader_handle
{
    public ke_scene_loader* @ref;

    [NativeTypeName("void (*)(ke_scene_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, void> destroy;
}
