using System.Numerics;
using KernelEngine.Physics;
using KernelEngine.Ecs;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A scene-graph node that attaches a single collision fixture to its nearest
/// <see cref="CollisionBody2D"/> ancestor. Idiom comes from Godot: bodies and shapes are separate
/// nodes so a single body can host multiple shapes by adding multiple <see cref="CollisionShape2D"/>
/// children — each with its own shape, material, and (eventually) local offset.
/// </summary>
/// <remarks>
/// <para>
/// MVP scope: the fixture is added in <see cref="Start"/> by walking up the tree to find a
/// <see cref="CollisionBody2D"/> ancestor. Adding the shape after the body's Start (e.g. spawning a
/// CollisionShape2D at runtime as a child of an existing body) works — the fixture is added then.
/// Removing the shape mid-game is <b>not yet supported</b>: <c>IPhysics2D</c> has no
/// <c>RemoveFixture</c>, so <see cref="OnDestroy"/> currently leaks the fixture (the body's
/// destruction eventually frees it). Surfaces in chapter 24 step 7+.
/// </para>
/// <para>
/// Local transform offset of this node relative to the body is not honored yet — the shape attaches
/// at the body origin. Box2D supports fixture-local transforms; wiring it through is a small follow-up.
/// </para>
/// </remarks>
public class CollisionShape2D : Node
{
    /// <summary>The shape geometry. Must be set before <see cref="Start"/> for the fixture to be attached.</summary>
    public Shape2D? Shape { get; set; }

    /// <summary>Per-fixture density (kg/m²). Body mass derives from sum of fixture mass.</summary>
    public float Density { get; set; } = 1f;

    /// <summary>Per-fixture friction coefficient (0..1 typical).</summary>
    public float Friction { get; set; } = 0.3f;

    /// <summary>Per-fixture restitution (bounciness, 0..1).</summary>
    public float Restitution { get; set; }

    protected override void Start()
    {
        base.Start();

        // Phase 5.3: pull scene-authored values from the bag (with current field
        // values as fallback so the legacy reflection path is not regressed).
        // Shape inline tables are forbidden in the new format (decision #4); the
        // scene file instead carries flat ShapeKind / ShapeHalfExtents / ShapeRadius
        // and CollisionShape2D builds the Shape2D itself here.
        Density     = Properties.GetFloat("Density",     Density);
        Friction    = Properties.GetFloat("Friction",    Friction);
        Restitution = Properties.GetFloat("Restitution", Restitution);

        if (Shape is null)
        {
            var kind = Properties.GetString("ShapeKind", "");
            if (kind == "rectangle")
            {
                Shape = new RectangleShape2D(Properties.GetVector2("ShapeHalfExtents", Vector2.One));
            }
            else if (kind == "circle")
            {
                Shape = new CircleShape2D(Properties.GetFloat("ShapeRadius", 0.5f));
            }
        }

        if (Shape is null) return;

        var body = FindBodyAncestor();
        if (body is null)
            throw new InvalidOperationException(
                $"{Name}: CollisionShape2D requires a CollisionBody2D ancestor in the tree.");

        body.AddCollider(Shape, Density, Friction, Restitution);
    }

    private CollisionBody2D? FindBodyAncestor()
    {
        for (var p = Parent; p is not null; p = p.Parent)
            if (p is CollisionBody2D b) return b;
        return null;
    }
}
