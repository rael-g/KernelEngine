using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Physics;

namespace Pong;

/// <summary>
/// The ball. Physics body + scoring logic. The visual is a Sprite2D child
/// declared in Ball.scene; fixture comes from CollisionShape2D child;
/// sounds come from AudioPlayer children (HitSound, ScoreSound).
/// </summary>
public sealed class Ball : Node, IPhysicsBody2D
{
    const float InitialSpeed   = 6f;
    const float GoalLineMargin = 0.5f;

    private readonly IPhysics2D                  _physics;
    private readonly IInputActionMap<PongAction> _actions;
    private readonly ISceneRouter                _router;

    private BodyHandle2D  _body;
    public BodyHandle2D   PhysicsBody => _body;

    private AudioPlayer? _hitSound;
    private AudioPlayer? _scoreSound;
    private Scoreboard?  _board;
    private Vector2      _lastVelocity;
    private bool         _awaitingLaunch = true;

    public Ball(IPhysics2D physics, IInputActionMap<PongAction> actions, ISceneRouter router)
    {
        _physics = physics;
        _actions = actions;
        _router  = router;
    }

    protected override void OnBind(NodeWorld nodeWorld)
    {
        var pos = new Vector2(LocalTransform.Position.X, LocalTransform.Position.Y);
        _body = _physics.CreateBody(BodyType2D.Dynamic, pos);
        // A square ball that tumbles reads as a bug. Its box collider picks up
        // spin from the two-point contact manifold even at zero friction, so the
        // rotation is locked rather than left to the solver.
        _physics.SetBodyFixedRotation(_body, true);
    }

    protected override void OnReady()
    {
        _hitSound   = NodeWorld!.Find<AudioPlayer>("HitSound");
        _scoreSound = NodeWorld!.Find<AudioPlayer>("ScoreSound");
    }

    protected override void OnUnbind() => _physics.DestroyBody(_body);

    protected override void OnUpdate(in View view)
    {
        if (_board is null)
        {
            _board = NodeWorld!.Find<Scoreboard>("Scoreboard")
                ?? throw new InvalidOperationException("Scene missing a 'Scoreboard' entity.");
            _board.ShowHint("Press Space to launch");
        }

        var state = _physics.GetBodyState(_body);
        LocalTransform = LocalTransform with
        {
            Position = new Vector3(state.Position.X, state.Position.Y, 0f),
            Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitZ, state.Angle),
        };

        if (_actions.IsJustPressed(PongAction.Quit,   in view)) _router.LoadScene("Menu");
        if (_actions.IsJustPressed(PongAction.Launch, in view) && _awaitingLaunch) Launch();

        if (_awaitingLaunch) return;

        var vel = state.Velocity;
        if (Math.Sign(vel.X) != Math.Sign(_lastVelocity.X) && _lastVelocity.X != 0)
            _hitSound?.Play();
        _lastVelocity = vel;

        if (state.Position.X >  Field.HalfW + GoalLineMargin) Score(leftScored: true);
        if (state.Position.X < -Field.HalfW - GoalLineMargin) Score(leftScored: false);
    }

    void Launch()
    {
        _awaitingLaunch = false;
        _board!.HideHint();
        float dirX = _board.Total % 2 == 0 ? 1f : -1f;
        float dirY = (Random.Shared.NextSingle() - 0.5f) * 0.6f;
        var v = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        _physics.SetBodyVelocity(_body, v);
        _lastVelocity = v;
    }

    void Score(bool leftScored)
    {
        _board!.RecordGoal(leftScored);
        _scoreSound?.Play();
        _physics.SetBodyPosition(_body, Vector2.Zero);
        _physics.SetBodyVelocity(_body, Vector2.Zero);
        _lastVelocity   = Vector2.Zero;
        _awaitingLaunch = true;
        _board.ShowHint("Press Space to launch");
    }
}
