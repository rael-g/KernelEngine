using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Physics;

namespace Pong;

/// <summary>
/// The ball. Composes <see cref="Body2D"/>, so its pose and motion are the physics
/// component itself and the physics plugin's own system advances them — this script
/// owns launch and scoring only. Visual, collider and sounds are children declared
/// in Ball.scene.
/// </summary>
public sealed partial class Ball : Body2D
{
    const float GoalLineMargin = 0.5f;

    private readonly IInputActionMap<PongAction> _actions;
    private readonly ISceneRouter                _router;

    /// <summary>Speed the ball is launched at, in metres per second.</summary>
    public partial float InitialSpeed { get; set; }

    /// <summary>Velocity seen last tick, used to detect the bounce that plays a sound.</summary>
    public partial Vector2 LastVelocity { get; set; }

    /// <summary>True while the ball waits at centre for the launch input.</summary>
    public partial bool AwaitingLaunch { get; set; }

    /// <summary>How many times the ball has been served, which decides serve direction.</summary>
    public partial int Launches { get; set; }

    public Ball(IInputActionMap<PongAction> actions, ISceneRouter router)
    {
        _actions       = actions;
        _router        = router;
        InitialSpeed   = 6f;
        AwaitingLaunch = true;
        Type           = BodyType2D.Dynamic;
        FixedRotation  = true;
    }

    void Update(in View view,
        [NodeName("HitSound")]   Child<AudioPlayer> hit,
        [NodeName("ScoreSound")] Child<AudioPlayer> sfx,
        Emit<GoalScored> goal,
        Emit<BallLaunched> launched)
    {
        if (_actions.IsJustPressed(PongAction.Quit, in view)) _router.LoadScene("Menu");

        if (_actions.IsJustPressed(PongAction.Launch, in view) && AwaitingLaunch) Launch(launched);
        if (AwaitingLaunch) return;

        if (Math.Sign(Velocity.X) != Math.Sign(LastVelocity.X) && LastVelocity.X != 0)
            hit.Node?.Play();
        LastVelocity = Velocity;

        if (Position.X >  Field.HalfW + GoalLineMargin) Score(leftScored: true,  goal, sfx);
        if (Position.X < -Field.HalfW - GoalLineMargin) Score(leftScored: false, goal, sfx);
    }

    void Launch(Emit<BallLaunched> launched)
    {
        AwaitingLaunch = false;
        launched.Send(new BallLaunched());
        // Alternating from the ball's own launch count rather than the scoreboard's
        // total: which way the ball serves is the ball's business, and reading it off
        // another node made a rule about serving depend on someone else keeping score.
        float dirX = Launches % 2 == 0 ? 1f : -1f;
        Launches++;
        float dirY = (Random.Shared.NextSingle() - 0.5f) * 0.6f;
        Velocity     = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        LastVelocity = Velocity;
    }

    void Score(bool leftScored, Emit<GoalScored> goal, Child<AudioPlayer> sfx)
    {
        goal.Send(new GoalScored(leftScored));
        sfx.Node?.Play();
        Position       = Vector2.Zero;
        Velocity       = Vector2.Zero;
        LastVelocity   = Vector2.Zero;
        AwaitingLaunch = true;
    }
}
