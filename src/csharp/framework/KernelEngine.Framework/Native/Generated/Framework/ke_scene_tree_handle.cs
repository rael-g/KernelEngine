using KernelEngine.Asset.Native;
using KernelEngine.Common.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_tree_handle
{
    public ke_scene_tree* @ref;

    [NativeTypeName("void (*)(ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> destroy;
}
