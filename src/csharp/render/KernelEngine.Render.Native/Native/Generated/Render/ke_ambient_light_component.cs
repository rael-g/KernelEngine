using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_ambient_light_component
{
    [NativeTypeName("ke_vec3")]
    public KernelEngine.Common.Native.ke_vec3 color;
}
