using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Base for all 2D physics nodes (chapter 24). A <see cref="CollisionBody2D"/> owns one body in the
/// active <see cref="IPhysics2D"/> world; collision shapes attach via <see cref="CollisionShape2D"/>
/// child nodes (Godot idiom) or, for code-style setup, via <see cref="AddCollider"/>. Game code never
/// sees <c>BodyHandle2D</c> or calls <c>IPhysics2D.Step</c> — pose properties write through to the
/// body, <see cref="Physics2DSystem"/> drives the simulation and syncs body state back into
/// <see cref="Node.LocalTransform"/>.
/// </summary>
/// <remarks>
/// Pose is in <b>world units = meters</b> (chapter 24 §7.5). Rotation is radians about the Z axis.
/// </remarks>
public abstract class CollisionBody2D : Node, IDisposable
{
    private readonly record struct PendingFixture(Shape2D Shape, float Density, float Friction, float Restitution);
    private readonly List<PendingFixture> _pendingFixtures = new(1);

    private IPhysics2D? _physics;
    private Physics2DSystem? _system;
    private BodyHandle2D _body;

    // Pre-Start staging: Position/Rotation/LinearVelocity writes land here until Start creates the
    // body, at which point we apply them to the world. After Start, properties read/write the body
    // directly. Decouples "configure the node" from "framework is ready" so callers can set the
    // pose right after construction without caring about lifecycle order.
    private Vector2 _pendingPosition;
    private float   _pendingRotation;
    private Vector2 _pendingLinearVelocity;

    /// <summary>The kind of body this subclass represents. Static/Kinematic/Dynamic.</summary>
    protected abstract BodyType2D BodyType { get; }

    /// <summary>Engine-internal: the underlying handle, exposed only to other framework code (e.g. <see cref="Physics2DSystem"/>).</summary>
    internal BodyHandle2D Body => _body;

    // ── Pose ─────────────────────────────────────────────────────────────────

    /// <summary>Body position in meters. Writing teleports the body; physics resumes from the new pose. Safe before Start (staged until body creation).</summary>
    public Vector2 Position
    {
        get => _physics is null || !_body.IsValid
                ? _pendingPosition
                : _physics.GetBodyState(_body).Position;
        set
        {
            if (_physics is null || !_body.IsValid) { _pendingPosition = value; return; }
            _physics.SetBodyPosition(_body, value, _physics.GetBodyState(_body).Angle);
        }
    }

    /// <summary>Rotation in radians about Z. Writing teleports the body. Safe before Start.</summary>
    public float Rotation
    {
        get => _physics is null || !_body.IsValid
                ? _pendingRotation
                : _physics.GetBodyState(_body).Angle;
        set
        {
            if (_physics is null || !_body.IsValid) { _pendingRotation = value; return; }
            _physics.SetBodyPosition(_body, _physics.GetBodyState(_body).Position, value);
        }
    }

    /// <summary>Linear velocity in meters/second. Setting it overwrites; physics does not blend. Safe before Start.</summary>
    public Vector2 LinearVelocity
    {
        get => _physics is null || !_body.IsValid
                ? _pendingLinearVelocity
                : _physics.GetBodyState(_body).Velocity;
        set
        {
            if (_physics is null || !_body.IsValid) { _pendingLinearVelocity = value; return; }
            _physics.SetBodyVelocity(_body, value);
        }
    }

    /// <summary>Angular velocity in radians/second. (Read-only in MVP — kernel API gap; setter comes when exposed.)</summary>
    public float AngularVelocity =>
        _physics is null || !_body.IsValid ? 0f : _physics.GetBodyState(_body).AngularVelocity;

    /// <summary>Teleports the body to a pose, skipping any motion blending.</summary>
    public void Teleport(Vector2 position, float rotation = 0f)
    {
        if (_physics is null || !_body.IsValid) return;
        _physics.SetBodyPosition(_body, position, rotation);
    }

    // ── Colliders ────────────────────────────────────────────────────────────

    /// <summary>
    /// Attaches a fixture with the given <paramref name="shape"/> and material parameters. Before
    /// <see cref="Start"/>, the fixture is staged and attached at body creation; afterward, it attaches
    /// immediately. Typically called by <see cref="CollisionShape2D"/> children — direct code use
    /// works too for setups that prefer the imperative style.
    /// </summary>
    public void AddCollider(Shape2D shape, float density = 1f, float friction = 0.3f, float restitution = 0f)
    {
        ArgumentNullException.ThrowIfNull(shape);
        var f = new PendingFixture(shape, density, friction, restitution);
        if (_physics is not null && _body.IsValid) AttachFixture(f);
        else _pendingFixtures.Add(f);
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    protected override void Start()
    {
        base.Start();

        _physics = Physics2DContext.PhysicsOrNull;
        _system  = Physics2DContext.SystemOrNull;
        if (_physics is null || _system is null)
            throw new InvalidOperationException(
                $"{GetType().Name}.Start: no 2D physics service is active. Add a 2D physics plugin (e.g. .AddBox2D(...)).");

        _body = _physics.CreateBody(BodyType, _pendingPosition);
        if (_pendingRotation != 0f)
            _physics.SetBodyPosition(_body, _pendingPosition, _pendingRotation);
        if (_pendingLinearVelocity != Vector2.Zero)
            _physics.SetBodyVelocity(_body, _pendingLinearVelocity);

        foreach (var f in _pendingFixtures) AttachFixture(f);
        _pendingFixtures.Clear();
        _system.Register(this);
    }

    protected override void OnDestroy()
    {
        base.OnDestroy();
        if (_physics is not null && _body.IsValid)
        {
            _system?.Unregister(this);
            _physics.DestroyBody(_body);
            _body = BodyHandle2D.None;
        }
    }

    public void Dispose() { /* handled in OnDestroy; here only so the framework's auto-Dispose path is happy */ }

    private void AttachFixture(PendingFixture f)
    {
        switch (f.Shape)
        {
            case RectangleShape2D r:
                _physics!.AddBoxFixture(_body, r.HalfExtents, f.Density, f.Friction, f.Restitution);
                break;
            case CircleShape2D c:
                _physics!.AddCircleFixture(_body, c.Radius, f.Density, f.Friction, f.Restitution);
                break;
            default:
                throw new NotSupportedException($"Shape type {f.Shape.GetType().Name} is not supported yet.");
        }
    }
}

/// <summary>Zero-mass body that never moves under simulation. Floors, walls, sensors-without-events.</summary>
public class StaticBody2D : CollisionBody2D
{
    protected override BodyType2D BodyType => BodyType2D.Static;
}

/// <summary>
/// Body moved by game code (<see cref="CollisionBody2D.Position"/>, <see cref="CollisionBody2D.LinearVelocity"/>)
/// but not by forces. Other dynamic bodies bounce off it. Use for paddles, platforms, characters.
/// </summary>
public class KinematicBody2D : CollisionBody2D
{
    protected override BodyType2D BodyType => BodyType2D.Kinematic;
}

/// <summary>
/// Fully simulated body — gravity, forces, and collisions all apply. Apply momentum via
/// <see cref="ApplyImpulse"/> (instant ΔV). Direct velocity writes still work but bypass mass.
/// </summary>
public class DynamicBody2D : CollisionBody2D
{
    protected override BodyType2D BodyType => BodyType2D.Dynamic;

    /// <summary>Applies a linear impulse (kg·m/s) at the body center.</summary>
    public void ApplyImpulse(Vector2 impulse)
    {
        if (Physics2DContext.PhysicsOrNull is { } phys && Body.IsValid)
            phys.ApplyImpulse(Body, impulse);
    }
}
