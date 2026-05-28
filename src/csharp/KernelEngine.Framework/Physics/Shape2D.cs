using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// Immutable description of a 2D collision shape — pure geometry, no material, no transform.
/// Material (density/friction/restitution) and transform offset belong to <see cref="CollisionShape2D"/>;
/// shapes are values that can be reused across fixtures.
/// </summary>
public abstract record Shape2D;

/// <summary>Axis-aligned rectangle; half-extents from the shape origin (meters).</summary>
public sealed record RectangleShape2D(Vector2 HalfExtents) : Shape2D;

/// <summary>Circle centered at the shape origin (radius in meters).</summary>
public sealed record CircleShape2D(float Radius) : Shape2D;
