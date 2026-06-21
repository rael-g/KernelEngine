using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Physics;

namespace Pong;

/// <summary>
/// Kinematic paddle. Physics body + input-driven movement. The visual is a
/// Sprite2D child declared in Paddle.scene; fixture comes from CollisionShape2D
/// child; MoveAction comes from the ECS PaddleComponent applied by the scene loader.
/// </summary>
public sealed class Paddle : Node, IPhysicsBody2D
{
    const float HalfH = 0.9f;
    const float Speed = 7f;

    private readonly IPhysics2D                  _physics;
    private readonly IInputActionMap<PongAction> _actions;

    private BodyHandle2D _body;
    public BodyHandle2D  PhysicsBody => _body;

    private PongAction _moveAction;
    private bool       _moveActionResolved;

    public Paddle(IPhysics2D physics, IInputActionMap<PongAction> actions)
    {
        _physics = physics;
        _actions = actions;
    }

    protected override void OnBind(NodeWorld nodeWorld)
    {
        var pos = new Vector2(LocalTransform.Position.X, LocalTransform.Position.Y);
        _body = _physics.CreateBody(BodyType2D.Kinematic, pos);
    }

    protected override void OnUnbind() => _physics.DestroyBody(_body);

    protected override void OnUpdate(in View view)
    {
        if (!_moveActionResolved)
        {
            _moveActionResolved = true;
            if (NodeWorld!.TryGetComponent<PaddleComponent>(Entity, "paddle", out var comp))
                _moveAction = comp.MoveAction;
        }

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
