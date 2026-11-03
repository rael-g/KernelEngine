using System.Numerics;

namespace KernelEngine.Physics;

public partial struct Collider2dComponent
{
    public ShapeKind2d Kind;
    public System.Numerics.Vector2 HalfExtents;

    public float Radius;

    public float Density;

    public float Friction;

    public float Restitution;
    public uint Layer;
    public uint Mask;

    public bool Attached;
}
