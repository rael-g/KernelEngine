using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Physics;

namespace Pong;

/// <summary>
/// The ball. Physics body + scoring logic. The visual is a Sprite2D child
/// declared in Ball.scene; sounds come from AudioPlayer children
/// (HitSound, ScoreSound).
/// </summary>
public sealed partial class Ball : Node2D
{
    const float InitialSpeed   = 6f;
    const float GoalLineMargin = 0.5f;

    static readonly Vector2 ShapeHalfExtents = new(0.18f, 0.18f);

    private readonly IPhysics2D                  _physics;
    private readonly IInputActionMap<PongAction> _actions;
    private readonly ISceneRouter                _router;

    private BodyHandle2D  _body;

    private Scoreboard?  _board;

    /// <summary>Velocity seen last tick, used to detect the bounce that plays a sound.</summary>
    public partial Vector2 LastVelocity { get; set; }

    /// <summary>True while the ball waits at centre for the launch input.</summary>
    public partial bool AwaitingLaunch { get; set; }

    public Ball(IPhysics2D physics, IInputActionMap<PongAction> actions, ISceneRouter router)
    {
        _physics = physics;
        _actions = actions;
        _router  = router;
    }

    protected override void OnReady()
    {
        _body = _physics.CreateBody(BodyType2D.Dynamic, Position);
        // A square ball that tumbles reads as a bug. Its box collider picks up
        // spin from the two-point contact manifold even at zero friction, so the
        // rotation is locked rather than left to the solver.
        _physics.SetBodyFixedRotation(_body, true);
        _physics.AddBoxFixture(_body, ShapeHalfExtents, friction: 0f, restitution: 1f);
    }

    protected override void OnUnbind() => _physics.DestroyBody(_body);

    void Update(in View view,
        [NodeName("HitSound")]   Child<AudioPlayer> hit,
        [NodeName("ScoreSound")] Child<AudioPlayer> sfx)
    {
        if (_board is null)
        {
            _board = NodeWorld!.Find<Scoreboard>("Scoreboard")
                ?? throw new InvalidOperationException("Scene missing a 'Scoreboard' entity.");
            _board.ShowHint("Press Space to launch");
        }

        var state = _physics.GetBodyState(_body);
        Position = state.Position;
        Rotation = state.Angle;

        if (_actions.IsJustPressed(PongAction.Quit,   in view)) _router.LoadScene("Menu");
        if (_actions.IsJustPressed(PongAction.Launch, in view) && AwaitingLaunch) Launch();

        if (AwaitingLaunch) return;

        var vel = state.Velocity;
        if (Math.Sign(vel.X) != Math.Sign(LastVelocity.X) && LastVelocity.X != 0)
            hit.Node?.Play();
        LastVelocity = vel;

        if (state.Position.X >  Field.HalfW + GoalLineMargin) Score(leftScored: true,  sfx);
        if (state.Position.X < -Field.HalfW - GoalLineMargin) Score(leftScored: false, sfx);
    }

    void Launch()
    {
        AwaitingLaunch = false;
        _board!.HideHint();
        float dirX = _board.Total % 2 == 0 ? 1f : -1f;
        float dirY = (Random.Shared.NextSingle() - 0.5f) * 0.6f;
        var v = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        _physics.SetBodyVelocity(_body, v);
        LastVelocity = v;
    }

    void Score(bool leftScored, Child<AudioPlayer> sfx)
    {
        _board!.RecordGoal(leftScored);
        sfx.Node?.Play();
        _physics.SetBodyPosition(_body, Vector2.Zero);
        _physics.SetBodyVelocity(_body, Vector2.Zero);
        LastVelocity   = Vector2.Zero;
        AwaitingLaunch = true;
        _board.ShowHint("Press Space to launch");
    }
}
