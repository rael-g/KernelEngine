using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// The ball. Looks up the sibling Scoreboard by name on first frame, drives
/// scoring + hit/score audio on subsequent frames. Edge-detects Launch + Quit
/// actions via the <see cref="IInputActionMap{TEnum}"/>.
/// </summary>
public sealed class Ball : MeshRenderer
{
    const float InitialSpeed   = 6f;
    const float GoalLineMargin = 0.5f;

    private readonly IPhysics2D                  _physics;
    private readonly IInputActionMap<PongAction> _actions;
    private readonly IAudio                      _audio;
    private readonly PongResources               _resources;
    private readonly ISceneRouter                _router;

    private BodyHandle2D _body;
    private Scoreboard?  _board;
    private Vector2      _lastVelocity;
    private bool         _awaitingLaunch = true;
    private bool         _prevLaunch;
    private bool         _prevQuit;

    public Ball(IPhysics2D physics, IInputActionMap<PongAction> actions, IAudio audio,
                PongResources resources, ISceneRouter router)
    {
        _physics   = physics;
        _actions   = actions;
        _audio     = audio;
        _resources = resources;
        _router    = router;
    }

    protected override void OnBind(NodeWorld nodeWorld)
    {
        MaterialHandle = _resources.WhiteMat;
        LocalTransform = LocalTransform with { Scale = new Vector3(0.36f, 0.36f, 1f) };
        base.OnBind(nodeWorld);

        _body = _physics.CreateBody(BodyType2D.Dynamic, Vector2.Zero);
        _physics.AddBoxFixture(_body, new Vector2(0.18f, 0.18f),
            density: 1f, friction: 0f, restitution: 1f);
    }

    protected override void OnUnbind() => _physics.DestroyBody(_body);

    protected override void OnUpdate(in View view)
    {
        if (_board is null)
        {
            // Late-bind the scoreboard on first frame — the scene loader
            // instantiates entities in declaration order; by the time any
            // node ticks, every other node already exists on the tree.
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

        bool launch = _actions.IsPressed(PongAction.Launch, in view);
        bool quit   = _actions.IsPressed(PongAction.Quit,   in view);
        if (quit   && !_prevQuit)                      _router.LoadScene("Menu");
        if (launch && !_prevLaunch && _awaitingLaunch) Launch();
        _prevLaunch = launch;
        _prevQuit   = quit;

        if (_awaitingLaunch) return;

        var vel = state.Velocity;
        if (Math.Sign(vel.X) != Math.Sign(_lastVelocity.X) && _lastVelocity.X != 0)
            _audio.Play(_resources.HitSound, volume: 0.5f);
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
        _audio.Play(_resources.ScoreSound, volume: 0.6f);
        _physics.SetBodyPosition(_body, Vector2.Zero);
        _physics.SetBodyVelocity(_body, Vector2.Zero);
        _lastVelocity   = Vector2.Zero;
        _awaitingLaunch = true;
        _board.ShowHint("Press Space to launch");
    }
}
