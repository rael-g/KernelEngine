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
        [NodeName("Scoreboard")] Ref<Scoreboard> board,
        [NodeName("HitSound")]   Child<AudioPlayer> hit,
        [NodeName("ScoreSound")] Child<AudioPlayer> sfx)
    {
        if (_actions.IsJustPressed(PongAction.Quit, in view)) _router.LoadScene("Menu");

        if (_actions.IsJustPressed(PongAction.Launch, in view) && AwaitingLaunch) Launch(board);
        if (AwaitingLaunch) return;

        if (Math.Sign(Velocity.X) != Math.Sign(LastVelocity.X) && LastVelocity.X != 0)
            hit.Node?.Play();
        LastVelocity = Velocity;

        if (Position.X >  Field.HalfW + GoalLineMargin) Score(leftScored: true,  board, sfx);
        if (Position.X < -Field.HalfW - GoalLineMargin) Score(leftScored: false, board, sfx);
    }

    void Launch(Ref<Scoreboard> board)
    {
        AwaitingLaunch = false;
        board.Node?.HideHint();
        float dirX = (board.Node?.Total ?? 0) % 2 == 0 ? 1f : -1f;
        float dirY = (Random.Shared.NextSingle() - 0.5f) * 0.6f;
        Velocity     = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        LastVelocity = Velocity;
    }

    void Score(bool leftScored, Ref<Scoreboard> board, Child<AudioPlayer> sfx)
    {
        board.Node?.RecordGoal(leftScored);
        sfx.Node?.Play();
        Position       = Vector2.Zero;
        Velocity       = Vector2.Zero;
        LastVelocity   = Vector2.Zero;
        AwaitingLaunch = true;
        board.Node?.ShowHint("Press Space to launch");
    }
}
