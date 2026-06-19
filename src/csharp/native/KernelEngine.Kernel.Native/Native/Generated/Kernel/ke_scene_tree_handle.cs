namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_scene_tree_handle
{
    public ke_scene_tree* @ref;

    [NativeTypeName("void (*)(ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> destroy;
}
