using System.Numerics;
using KernelEngine.Framework;

namespace Pong;

/// <summary>
/// The left or right paddle. Constructed by SceneLoader (DI-injected
/// <see cref="IInputActionReader{TEnum}"/>); the <see cref="MoveAction"/> is set per-instance
/// from the scene file (<c>PaddleLeftMove</c> / <c>PaddleRightMove</c>).
/// </summary>
public sealed class Paddle(IInputActionReader<PongAction> actions) : KinematicBody2D
{
    const float HalfH = 0.9f;
    const float Speed = 7f;

    public PongAction MoveAction { get; set; }

    protected override void Start()
    {
        // New scene format ([entity.properties] MoveAction = "PaddleLeftMove"): parse the string
        // into the enum. Legacy format already set MoveAction via reflection; the bag has no key
        // and the parse fallback keeps the existing value.
        var actionName = Properties.GetString("MoveAction", MoveAction.ToString());
        if (Enum.TryParse<PongAction>(actionName, ignoreCase: true, out var parsed))
            MoveAction = parsed;
        base.Start();
    }

    protected override void Update(float dt)
    {
        float vy = actions.GetActionAxis1D(MoveAction) * Speed;

        // Velocity clamp at the boundaries — refuse motion that would leave the play area
        // (avoids the 1-frame overshoot of position-clamping with a fixed-step physics loop).
        var pos = Position;
        float maxY = Field.HalfH - Field.WallThickness - HalfH;
        if (vy > 0 && pos.Y >= maxY) vy = 0;
        if (vy < 0 && pos.Y <= -maxY) vy = 0;

        LinearVelocity = new Vector2(0, vy);
    }
}
