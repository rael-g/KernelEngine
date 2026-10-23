using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Physics.Native;

public unsafe partial struct ke_physics_body2d_module_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_ecs *")]
    public KernelEngine.Ecs.Native.ke_ecs* ecs;

    public ke_physics_2d* physics;

    [NativeTypeName("ke_scene_tree *")]
    public KernelEngine.Framework.Native.ke_scene_tree* scene_tree;
}
