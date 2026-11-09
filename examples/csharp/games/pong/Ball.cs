using System.ComponentModel.DataAnnotations;
using System.Numerics;

using KernelEngine.Framework.Nodes;

namespace Pong;

/// <summary>The ball: served on Launch, bounces with a sound, and scores past a goal line.</summary>
[NodeType("pong.ball")]
partial class Ball(Game game) : Body2D
{
    const float FieldHalfWidth = 8.0f;
    const float GoalLineMargin = 0.5f;
    const float ServeSpread = 0.6f;

    /// <summary>The sound of a bounce.</summary>
    [Export, MaxLength(256)] public partial string HitSound { get; set; }

    /// <summary>The bounce's volume.</summary>
    [Export] public partial float HitVolume { get; set; }

    /// <summary>The sound of a goal.</summary>
    [Export, MaxLength(256)] public partial string ScoreSound { get; set; }

    /// <summary>The goal's volume.</summary>
    [Export] public partial float ScoreVolume { get; set; }

    /// <summary>The speed a serve starts at.</summary>
    [Export] public partial float InitialSpeed { get; set; }

    /// <summary>Whether the ball waits at the centre for Launch.</summary>
    [Export] public partial bool AwaitingLaunch { get; set; }

    partial Vector2 LastVelocity { get; set; }

    partial bool LaunchRequested { get; set; }

    partial int Launches { get; set; }

    void Initial()
    {
        HitVolume = 1.0f;
        ScoreVolume = 1.0f;
        InitialSpeed = 6.0f;
        AwaitingLaunch = true;
    }

    void Update()
    {
        if (Pressed(game.Quit)) ChangeScene(Scenes.Menu);
        else if (Pressed(game.Launch) && AwaitingLaunch) LaunchRequested = true;
    }

    void FixedUpdate()
    {
        if (LaunchRequested) Serve();
        if (AwaitingLaunch) return;

        var bounced = LastVelocity.X != 0 && (Body.Velocity.X > 0) != (LastVelocity.X > 0);
        LastVelocity = Body.Velocity;
        if (bounced) PlaySound(HitSound, HitVolume);

        var leftScored = Transform2D.Position.X > FieldHalfWidth + GoalLineMargin;
        if (!leftScored && Transform2D.Position.X >= -FieldHalfWidth - GoalLineMargin) return;
        Raise(new GoalScored { LeftScored = leftScored });
        Transform2D.Position = Vector2.Zero;
        Body.Velocity = Vector2.Zero;
        LastVelocity = Vector2.Zero;
        AwaitingLaunch = true;
        PlaySound(ScoreSound, ScoreVolume);
    }

    void Serve()
    {
        AwaitingLaunch = false;
        LaunchRequested = false;
        Raise(new BallLaunched { Launched = true });
        var dirX = Launches % 2 == 0 ? 1.0f : -1.0f;
        Launches++;
        var dirY = (Random.Shared.NextSingle() - 0.5f) * ServeSpread;
        Body.Velocity = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        LastVelocity = Body.Velocity;
    }
}
