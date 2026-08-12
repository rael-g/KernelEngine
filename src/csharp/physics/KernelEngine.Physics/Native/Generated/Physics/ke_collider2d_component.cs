using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Native;

public partial struct ke_collider2d_component
{
    public ke_shape_kind_2d kind;

    public ke_vec2 half_extents;

    public float radius;

    public float density;

    public float friction;

    public float restitution;

    public bool attached;
}
