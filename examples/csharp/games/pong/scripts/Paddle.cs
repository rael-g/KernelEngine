using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// Kinematic paddle. Position is owned by Box2D; the node syncs its world
/// transform from the body each frame, then drives a vertical velocity from
/// the assigned action axis. Velocity is clamped at the playable boundaries
/// to avoid the 1-frame overshoot of position-clamping.
/// </summary>
public sealed class Paddle : MeshRenderer
{
    const float HalfH = 0.9f;
    const float Speed = 7f;

    private readonly IPhysics2D                  _physics;
    private readonly IInputActionMap<PongAction> _actions;
    private readonly Vector2                     _initialPos;
    private readonly PongAction                  _moveAction;

    private BodyHandle2D _body;

    public Paddle(IPhysics2D physics, IInputActionMap<PongAction> actions, MaterialHandle mat,
                  Vector2 initialPos, PongAction moveAction)
    {
        _physics    = physics;
        _actions    = actions;
        _initialPos = initialPos;
        _moveAction = moveAction;
        MaterialHandle = mat;
    }

    protected override void OnBind(Tree tree)
    {
        LocalTransform = LocalTransform with
        {
            Position = new Vector3(_initialPos.X, _initialPos.Y, 0f),
            Scale    = new Vector3(0.3f, 1.8f, 1f),
        };
        base.OnBind(tree);

        _body = _physics.CreateBody(BodyType2D.Kinematic, _initialPos);
        _physics.AddBoxFixture(_body, new Vector2(0.15f, HalfH), restitution: 1f);
    }

    protected override void OnUpdate(in View view)
    {
        var state = _physics.GetBodyState(_body);
        LocalTransform = LocalTransform with
        {
            Position = new Vector3(state.Position.X, state.Position.Y, 0f),
        };

        float vy = _actions.GetAxis1D(_moveAction, in view) * Speed;

        float maxY = Field.HalfH - Field.WallThickness - HalfH;
        if (vy > 0 && state.Position.Y >=  maxY) vy = 0;
        if (vy < 0 && state.Position.Y <= -maxY) vy = 0;

        _physics.SetBodyVelocity(_body, new Vector2(0f, vy));
    }
}
