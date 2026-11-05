using System.Numerics;

using KernelEngine.Framework;
using KernelEngine.Physics;

namespace Pong;

/// <summary>
/// The ball. Composes <see cref="Body2D"/>, so its pose and motion are the physics
/// component itself and the physics plugin's own system advances them — this script
/// owns launch and scoring only, reading input each frame and touching the body each
/// fixed step. Visual and collider are children declared in Ball.scene; each sound is a scene of its own, spawned under the ball when it plays.
/// </summary>
public sealed partial class Ball : Body2D
{
    const float GoalLineMargin = 0.5f;

    private readonly ISceneRouter _router;

    /// <summary>The sound played each time the ball bounces off a paddle.</summary>
    public partial SceneRef HitSound { get; set; }

    /// <summary>The sound played each time a goal is scored.</summary>
    public partial SceneRef ScoreSound { get; set; }

    /// <summary>The action that serves the ball.</summary>
    public partial InputAction Launch { get; set; }

    /// <summary>The action that leaves the match for the menu.</summary>
    public partial InputAction Quit { get; set; }

    /// <summary>Speed the ball is launched at, in metres per second.</summary>
    public partial float InitialSpeed { get; set; }

    /// <summary>Velocity seen last tick, used to detect the bounce that plays a sound.</summary>
    public partial Vector2 LastVelocity { get; set; }

    /// <summary>True while the ball waits at centre for the launch input.</summary>
    public partial bool AwaitingLaunch { get; set; }

    /// <summary>True from the frame the launch input is pressed until the next fixed step serves.</summary>
    public partial bool LaunchRequested { get; set; }

    /// <summary>How many times the ball has been served, which decides serve direction.</summary>
    public partial int Launches { get; set; }

    public Ball(ISceneRouter router)
    {
        _router = router;
        Launch = "Launch";
        Quit = "Quit";
        InitialSpeed = 6f;
        AwaitingLaunch = true;
        Type = BodyType2D.Dynamic;
        FixedRotation = true;
    }

    void Update(in View view)
    {
        if (Quit.JustPressed) _router.LoadScene<Scenes.Menu>();
        if (Launch.JustPressed && AwaitingLaunch) LaunchRequested = true;
    }

    void FixedUpdate(in View view,
        Emit<GoalScored> goal,
        Emit<BallLaunched> launched)
    {
        if (LaunchRequested) Serve(launched);
        if (AwaitingLaunch) return;

        if (Math.Sign(Velocity.X) != Math.Sign(LastVelocity.X) && LastVelocity.X != 0)
            HitSound.Spawn();
        LastVelocity = Velocity;

        if (Position.X > Field.HalfW + GoalLineMargin) Score(leftScored: true, goal);
        if (Position.X < -Field.HalfW - GoalLineMargin) Score(leftScored: false, goal);
    }

    void Serve(Emit<BallLaunched> launched)
    {
        AwaitingLaunch = false;
        LaunchRequested = false;
        launched.Send(new BallLaunched());
        float dirX = Launches % 2 == 0 ? 1f : -1f;
        Launches++;
        float dirY = (Random.Shared.NextSingle() - 0.5f) * 0.6f;
        Velocity = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        LastVelocity = Velocity;
    }

    void Score(bool leftScored, Emit<GoalScored> goal)
    {
        goal.Send(new GoalScored(leftScored));
        ScoreSound.Spawn();
        Position = Vector2.Zero;
        Velocity = Vector2.Zero;
        LastVelocity = Vector2.Zero;
        AwaitingLaunch = true;
    }
}
