using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Configuration.Native;
using KernelEngine.Physics.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Physics.Box2D.Native;

public partial struct ke_physics_2d_box2d_config
{
    public float gravity_x;

    public float gravity_y;
}
