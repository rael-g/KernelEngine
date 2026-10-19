using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_component_set_handle
{
    public ke_scene_component_set* @ref;

    [NativeTypeName("void (*)(ke_scene_component_set *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_component_set*, void> destroy;
}
