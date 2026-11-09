using System.Numerics;

namespace KernelEngine.Common;

public partial struct Transform2DComponent
{
    public System.Numerics.Vector2 Position;

    public float Rotation;
    public System.Numerics.Vector2 Scale;

    public float Depth;
}
