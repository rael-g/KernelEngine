using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Physics;

namespace Pong;

/// <summary>
/// Kinematic paddle driven by input. Composes <see cref="Body2D"/>, so movement is a
/// write to <c>Velocity</c> and the physics plugin advances it.
/// </summary>
public sealed partial class Paddle : Body2D
{
    const float HalfH = 0.9f;
    const float Speed = 7f;

    private readonly IInputActionMap<PongAction> _actions;

    /// <summary>Which action moves this paddle. Authored per instance in the scene.</summary>
    public partial PongAction MoveAction { get; set; }

    public Paddle(IInputActionMap<PongAction> actions)
    {
        _actions = actions;
        Type     = BodyType2D.Kinematic;
    }

    void Update(in View view)
    {
        float vy = _actions.GetAxis1D(MoveAction, in view) * Speed;

        float maxY = Field.HalfH - Field.WallThickness - HalfH;
        if (vy > 0 && Position.Y >=  maxY) vy = 0;
        if (vy < 0 && Position.Y <= -maxY) vy = 0;

        Velocity = new Vector2(0f, vy);
    }
}
