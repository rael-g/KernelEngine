using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_spot_light_component
{
    [NativeTypeName("ke_vec3")]
    public KernelEngine.Common.Native.ke_vec3 direction;

    [NativeTypeName("ke_vec3")]
    public KernelEngine.Common.Native.ke_vec3 color;

    public float intensity;

    public float range;

    public float inner_angle;

    public float outer_angle;
}
