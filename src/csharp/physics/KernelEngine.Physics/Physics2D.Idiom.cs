using System.Numerics;

namespace KernelEngine.Physics;

/// <summary>
/// The parts of <see cref="Physics2D"/> that express the native surface in C# terms
/// rather than mirroring it: <see cref="Vector2"/> for coordinate pairs the ABI
/// passes as loose floats, the <see cref="BodyHandle2D"/> value type over a bare
/// uint id, the record-struct <see cref="BodyState2D"/> projection, and the
/// "invalid handle is a silent no-op" policy the managed contract promises but the
/// ABI does not. Everything that is a direct image of the C ABI is generated in
/// <c>Generated/Physics2D.g.cs</c>.
/// </summary>
public unsafe partial class Physics2D : IPhysics2D
{
    /// <inheritdoc/>
    public void SetGravity(Vector2 gravity) => SetGravity(gravity.X, gravity.Y);

    /// <inheritdoc/>
    BodyHandle2D IPhysics2D.CreateBody(BodyType2D type, Vector2 position)
    {
        var id = CreateBody(type, position.X, position.Y);
        return id != 0 ? new BodyHandle2D(id) : BodyHandle2D.None;
    }

    /// <inheritdoc/>
    public void DestroyBody(BodyHandle2D body)
    {
        if (body.IsValid) DestroyBody(body.Value);
    }

    /// <inheritdoc/>
    public void AddBoxFixture(BodyHandle2D body, Vector2 halfExtents,
        float density = 1f, float friction = 0.3f, float restitution = 0f)
    {
        if (body.IsValid) AddBoxFixture(body.Value, halfExtents.X, halfExtents.Y, density, friction, restitution);
    }

    /// <inheritdoc/>
    public void AddCircleFixture(BodyHandle2D body, float radius,
        float density = 1f, float friction = 0.3f, float restitution = 0f)
    {
        if (body.IsValid) AddCircleFixture(body.Value, radius, density, friction, restitution);
    }

    /// <inheritdoc/>
    public void SetBodyPosition(BodyHandle2D body, Vector2 position, float angle)
    {
        if (body.IsValid) SetBodyPosition(body.Value, position.X, position.Y, angle);
    }

    /// <inheritdoc/>
    public void SetBodyVelocity(BodyHandle2D body, Vector2 velocity)
    {
        if (body.IsValid) SetBodyVelocity(body.Value, velocity.X, velocity.Y);
    }

    /// <inheritdoc/>
    public void ApplyImpulse(BodyHandle2D body, Vector2 impulse)
    {
        if (body.IsValid) ApplyImpulse(body.Value, impulse.X, impulse.Y);
    }

    /// <inheritdoc/>
    public void SetBodyFixedRotation(BodyHandle2D body, bool locked)
    {
        if (body.IsValid) SetBodyFixedRotation(body.Value, locked);
    }

    /// <inheritdoc/>
    BodyState2D IPhysics2D.GetBodyState(BodyHandle2D body)
    {
        if (!body.IsValid) return default;
        var s = GetBodyState(body.Value);
        return new BodyState2D(new Vector2(s.x, s.y), s.angle,
            new Vector2(s.velocity_x, s.velocity_y), s.angular_velocity);
    }
}
