using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Native;

public partial struct ke_body2d_component
{
    public ke_body_type_2d type;

    [NativeTypeName("ke_vec2")]
    public KernelEngine.Common.Native.ke_vec2 position;

    public float angle;

    [NativeTypeName("ke_vec2")]
    public KernelEngine.Common.Native.ke_vec2 velocity;

    public float angular_velocity;

    public float gravity_scale;

    public bool fixed_rotation;

    [NativeTypeName("ke_body_2d")]
    public uint body;
}
