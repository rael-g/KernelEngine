using System.Numerics;

namespace KernelEngine.Physics;

/// <summary>
/// Body kind in a 2D rigid-body world.
/// </summary>
public enum BodyType2D
{
    /// <summary>Never moves; infinite mass. Floors, walls.</summary>
    Static = 0,
    /// <summary>Moved by code only; ignores forces and collisions push it.</summary>
    Kinematic = 1,
    /// <summary>Full simulation: gravity, forces, collisions all apply.</summary>
    Dynamic = 2,
}

/// <summary>Opaque per-world handle for a body. Compare with <see cref="None"/> for validity.</summary>
public readonly record struct BodyHandle2D(uint Value)
{
    public static readonly BodyHandle2D None = new(0);
    public bool IsValid => Value != 0;
}

/// <summary>Snapshot of a body's pose and motion at a point in time.</summary>
public readonly record struct BodyState2D(
    Vector2 Position,
    float   Angle,
    Vector2 Velocity,
    float   AngularVelocity);

/// <summary>
/// Managed mirror of the C kernel's <c>ke_physics_2d</c> vtable — a 2D rigid-body world.
/// Concrete implementations come from plugin libraries (e.g. <c>KernelEngine.Physics.Box2D</c>).
/// Not thread-safe: call all methods on the same thread (typically ke.sim).
/// </summary>
public interface IPhysics2D : IDisposable
{
    /// <summary>Sets world gravity (m/s²). Default is (0, -9.81).</summary>
    void SetGravity(Vector2 gravity);

    /// <summary>Advances the simulation by <paramref name="deltaTime"/> seconds.</summary>
    void Step(float deltaTime);

    /// <summary>Creates a body at <paramref name="position"/>.</summary>
    BodyHandle2D CreateBody(BodyType2D type, Vector2 position);

    /// <summary>Destroys the body and all its fixtures. Safe on <see cref="BodyHandle2D.None"/>.</summary>
    void DestroyBody(BodyHandle2D body);

    /// <summary>Attaches an axis-aligned box fixture (half-extents from body origin).</summary>
    void AddBoxFixture(BodyHandle2D body, Vector2 halfExtents, float density = 1f, float friction = 0.3f, float restitution = 0f);

    /// <summary>Attaches a circle fixture centered at the body origin.</summary>
    void AddCircleFixture(BodyHandle2D body, float radius, float density = 1f, float friction = 0.3f, float restitution = 0f);

    /// <summary>Reads the body's current pose and motion.</summary>
    BodyState2D GetBodyState(BodyHandle2D body);

    /// <summary>Teleports the body — skips collision response.</summary>
    void SetBodyPosition(BodyHandle2D body, Vector2 position, float angle = 0f);

    /// <summary>Sets linear velocity directly (m/s).</summary>
    void SetBodyVelocity(BodyHandle2D body, Vector2 velocity);

    /// <summary>Applies a linear impulse (kg·m/s) at the body center.</summary>
    void ApplyImpulse(BodyHandle2D body, Vector2 impulse);
}
