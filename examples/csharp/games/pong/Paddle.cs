using System.Numerics;

using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;

namespace Pong;

/// <summary>A paddle: moves up and down along its action's axis, kept inside the walls.</summary>
[NodeType("pong.paddle")]
partial class Paddle : Body2D
{
    const float FieldHalfHeight = 4.5f;
    const float WallHalfThickness = 0.25f;

    /// <summary>The axis action moving the paddle.</summary>
    [Export] public partial ActionRef MoveAction { get; set; }

    /// <summary>Speed in metres per second.</summary>
    [Export] public partial float Speed { get; set; }

    /// <summary>Half the paddle's height, which keeps it inside the walls.</summary>
    [Export] public partial float HalfHeight { get; set; }

    /// <summary>A paddle as it is born.</summary>
    public Paddle()
    {
        Speed = 7.0f;
        HalfHeight = 0.9f;
    }

    void FixedUpdate()
    {
        var action = MoveAction;
        var vy = Axis(ref action) * Speed;
        MoveAction = action;
        var maxY = FieldHalfHeight - WallHalfThickness - HalfHeight;
        if (vy > 0 && Transform2d.Position.Y >= maxY) vy = 0;
        if (vy < 0 && Transform2d.Position.Y <= -maxY) vy = 0;
        Body2d.Velocity = new Vector2(0.0f, vy);
    }
}
