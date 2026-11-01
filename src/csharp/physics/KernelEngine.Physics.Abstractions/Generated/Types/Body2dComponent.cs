using System.Numerics;

namespace KernelEngine.Physics;

public partial struct Body2dComponent
{
    public BodyType2D Type;
    public System.Numerics.Vector2 Velocity;

    public float AngularVelocity;

    public float GravityScale;

    public bool FixedRotation;
    public uint Body;
}
