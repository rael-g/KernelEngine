using KernelEngine.Kernel.Native;

namespace KernelEngine.Physics.Box2D.Native;

public unsafe partial struct ke_physics_2d_box2d_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Kernel.Native.ke_logger* logger;

    public float gravity_x;

    public float gravity_y;
}
