using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// Kinematic paddle. The scene file sets <see cref="MoveAction"/> + initial
/// <c>Position</c>; DI fills the rest. The body is created at OnBind time
/// at the bound-in transform position.
/// </summary>
public sealed class Paddle : MeshRenderer
{
    const float HalfH = 0.9f;
    const float Speed = 7f;

    private readonly IPhysics2D                  _physics;
    private readonly IInputActionMap<PongAction> _actions;
    private readonly PongResources               _resources;

    private BodyHandle2D _body;

    /// <summary>Set by SceneLoader from <c>[entity.properties] MoveAction</c>.</summary>
    public PongAction MoveAction { get; set; }

    public Paddle(IPhysics2D physics, IInputActionMap<PongAction> actions, PongResources resources)
    {
        _physics   = physics;
        _actions   = actions;
        _resources = resources;
    }

    protected override void OnBind(Tree tree)
    {
        MaterialHandle = _resources.WhiteMat;
        LocalTransform = LocalTransform with { Scale = new Vector3(0.3f, 1.8f, 1f) };
        base.OnBind(tree);

        var pos = new Vector2(LocalTransform.Position.X, LocalTransform.Position.Y);
        _body = _physics.CreateBody(BodyType2D.Kinematic, pos);
        _physics.AddBoxFixture(_body, new Vector2(0.15f, HalfH), restitution: 1f);
    }

    protected override void OnUnbind() => _physics.DestroyBody(_body);

    protected override void OnUpdate(in View view)
    {
        var state = _physics.GetBodyState(_body);
        LocalTransform = LocalTransform with
        {
            Position = new Vector3(state.Position.X, state.Position.Y, 0f),
        };

        float vy = _actions.GetAxis1D(MoveAction, in view) * Speed;

        float maxY = Field.HalfH - Field.WallThickness - HalfH;
        if (vy > 0 && state.Position.Y >=  maxY) vy = 0;
        if (vy < 0 && state.Position.Y <= -maxY) vy = 0;

        _physics.SetBodyVelocity(_body, new Vector2(0f, vy));
    }
}
