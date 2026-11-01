using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct SpotLightComponent
{
    public System.Numerics.Vector3 Direction;
    public System.Numerics.Vector3 Color;

    public float Intensity;

    public float Range;

    public float InnerAngle;

    public float OuterAngle;
}
