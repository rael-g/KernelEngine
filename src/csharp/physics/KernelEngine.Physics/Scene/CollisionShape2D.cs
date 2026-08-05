using System.Numerics;
using KernelEngine.Physics;

namespace KernelEngine.Framework;

/// <summary>
/// Node that attaches a single 2D collision fixture to the nearest
/// <see cref="IPhysicsBody2D"/> ancestor.
/// Scene-file properties: <c>ShapeKind</c> ("rectangle" | "circle"),
/// <c>ShapeHalfExtents</c> (vec2, rectangle), <c>ShapeRadius</c> (float, circle),
/// <c>Density</c> (float, default 1), <c>Friction</c> (float, default 0.3),
/// <c>Restitution</c> (float, default 0).
/// </summary>
public class CollisionShape2D : Node
{
    private readonly IPhysics2D _physics;

    public CollisionShape2D(IPhysics2D physics) => _physics = physics;

    protected internal override void OnBind(NodeWorld nodeWorld) { }

    protected internal override void OnReady()
    {
        var body = FindBodyAncestor();
        if (body is null) return;

        float density     = 1f;
        float friction    = 0.3f;
        float restitution = 0f;

        if (!TryGetProperties(out var props)) return;

        props.TryGetFloat("Density",     out density);
        props.TryGetFloat("Friction",    out friction);
        props.TryGetFloat("Restitution", out restitution);

        if (density     == 0f) density     = 1f;

        props.TryGetString("ShapeKind", out var kind);
        switch (kind)
        {
            case "rectangle":
            {
                var half = Vector2.One * 0.5f;
                if (props.TryGetVec2("ShapeHalfExtents", out var v))
                    half = v;
                _physics.AddBoxFixture(body.PhysicsBody, half, density, friction, restitution);
                break;
            }
            case "circle":
            {
                float radius = 0.5f;
                props.TryGetFloat("ShapeRadius", out radius);
                if (radius == 0f) radius = 0.5f;
                _physics.AddCircleFixture(body.PhysicsBody, radius, density, friction, restitution);
                break;
            }
        }
    }

    private IPhysicsBody2D? FindBodyAncestor()
    {
        for (var p = Parent; p is not null; p = p.Parent)
            if (p is IPhysicsBody2D b) return b;
        return null;
    }
}
