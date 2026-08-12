using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Native;

public unsafe partial struct ke_physics_body2d_module_params
{
    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("ke_ecs *")]
    public KernelEngine.Ecs.Native.ke_ecs* ecs;

    [NativeTypeName("ke_physics_2d *")]
    public KernelEngine.Physics.Native.ke_physics_2d* physics;
}
