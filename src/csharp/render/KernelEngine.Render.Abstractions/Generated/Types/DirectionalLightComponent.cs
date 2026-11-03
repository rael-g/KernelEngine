using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct DirectionalLightComponent
{
    public System.Numerics.Vector3 Direction;
    public System.Numerics.Vector3 Color;

    public float Intensity;
    public System.Numerics.Vector3 Ambient;
}
