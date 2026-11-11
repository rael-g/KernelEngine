using System.ComponentModel.DataAnnotations;
using System.Numerics;

using KernelEngine.Framework.Nodes;

namespace Pong;

/// <summary>The ball: served when the match asks, bounces with a sound, and reports a goal past a goal line.</summary>
[NodeType("pong.ball")]
partial class Ball : Body2D
{
    const float FieldHalfWidth = 8.0f;
    const float GoalLineMargin = 0.5f;
    const float ServeSpread = 0.6f;

    /// <summary>The sound of a bounce.</summary>
    [Export, MaxLength(256)] public partial string HitSound { get; set; }

    /// <summary>The bounce's volume.</summary>
    [Export] public partial float HitVolume { get; set; }

    /// <summary>The speed a serve starts at.</summary>
    [Export] public partial float InitialSpeed { get; set; }

    partial Vector2 LastVelocity { get; set; }

    partial int Serves { get; set; }

    public Ball()
    {
        HitVolume = 1.0f;
        InitialSpeed = 6.0f;
    }

    [On<ServeRequested>]
    void OnServe(ServeRequested _)
    {
        var dirX = Serves % 2 == 0 ? 1.0f : -1.0f;
        Serves++;
        var dirY = (Random.Shared.NextSingle() - 0.5f) * ServeSpread;
        Body.Velocity = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        LastVelocity = Body.Velocity;
    }

    void FixedUpdate()
    {
        var bounced = LastVelocity.X != 0 && (Body.Velocity.X > 0) != (LastVelocity.X > 0);
        LastVelocity = Body.Velocity;
        if (bounced) Spawn("Sound", Sounds.Once(HitSound, HitVolume));

        var leftScored = Transform2D.Position.X > FieldHalfWidth + GoalLineMargin;
        if (!leftScored && Transform2D.Position.X >= -FieldHalfWidth - GoalLineMargin) return;
        Transform2D.Position = Vector2.Zero;
        Body.Velocity = Vector2.Zero;
        LastVelocity = Vector2.Zero;
        Raise(new GoalScored { LeftScored = leftScored });
    }
}
