using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct PointLightComponent
{
    public System.Numerics.Vector3 Color;

    public float Intensity;

    public float Radius;
}
