using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_world_params
{
    [NativeTypeName("ke_ecs *")]
    public KernelEngine.Ecs.Native.ke_ecs* ecs;

    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("struct ke_scene_tree *")]
    public ke_scene_tree* scene_tree;

    [NativeTypeName("struct ke_signal_bus *")]
    public ke_signal_bus* signal_bus;
}
