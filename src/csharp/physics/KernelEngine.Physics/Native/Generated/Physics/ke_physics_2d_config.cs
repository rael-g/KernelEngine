using System.Numerics;

using global::KernelEngine.Common;
using global::KernelEngine.Physics;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Physics.Native;

public partial struct ke_physics_2d_config
{
    public float gravity_x;

    public float gravity_y;
}
