using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// Kinematic paddle. Position is owned by Box2D (the body); the node syncs
/// its world transform from the body every frame, then sets a vertical
/// velocity based on its two assigned key codes. Velocity is clamped at the
/// playable boundaries to avoid 1-frame overshoot from position-clamping.
/// </summary>
public sealed class Paddle : MeshRenderer
{
    const float HalfH = 0.9f;
    const float Speed = 7f;

    private readonly IPhysics2D _physics;
    private readonly Vector2    _initialPos;
    private readonly int        _keyDown;
    private readonly int        _keyUp;

    private BodyHandle2D _body;

    public Paddle(IPhysics2D physics, MaterialHandle mat, Vector2 initialPos, int keyDown, int keyUp)
    {
        _physics    = physics;
        _initialPos = initialPos;
        _keyDown    = keyDown;
        _keyUp      = keyUp;
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

        float axis = (view.IsKeyDown(_keyUp) ? 1f : 0f) - (view.IsKeyDown(_keyDown) ? 1f : 0f);
        float vy   = axis * Speed;

        float maxY = Field.HalfH - Field.WallThickness - HalfH;
        if (vy > 0 && state.Position.Y >=  maxY) vy = 0;
        if (vy < 0 && state.Position.Y <= -maxY) vy = 0;

        _physics.SetBodyVelocity(_body, new Vector2(0f, vy));
    }
}
