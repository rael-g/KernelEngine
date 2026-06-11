using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// The ball. Tracks scoring + plays hit/score sound effects. Edge-detects
/// Space (launch) and Escape (quit) via View polling — the legacy InputEvent
/// pipeline isn't ported to the new Framework yet.
/// </summary>
public sealed class Ball : MeshRenderer
{
    const int   KeySpace      = 32;
    const int   KeyEscape     = 256;
    const float InitialSpeed  = 6f;
    const float GoalLineMargin = 0.5f;

    private readonly Tree           _tree;
    private readonly IPhysics2D     _physics;
    private readonly IAudio         _audio;
    private readonly SoundHandle    _hit;
    private readonly SoundHandle    _score;
    private readonly Scoreboard     _board;
    private readonly MaterialHandle _mat;

    private BodyHandle2D _body;
    private Vector2      _lastVelocity;
    private bool         _awaitingLaunch = true;
    private bool         _prevSpace;
    private bool         _prevEsc;

    public Ball(Tree tree, IPhysics2D physics, MaterialHandle mat,
                IAudio audio, SoundHandle hit, SoundHandle score, Scoreboard board)
    {
        _tree    = tree;
        _physics = physics;
        _mat     = mat;
        _audio   = audio;
        _hit     = hit;
        _score   = score;
        _board   = board;
    }

    protected override void OnBind(Tree tree)
    {
        MaterialHandle = _mat;
        LocalTransform = LocalTransform with { Scale = new Vector3(0.36f, 0.36f, 1f) };
        base.OnBind(tree);

        _body = _physics.CreateBody(BodyType2D.Dynamic, Vector2.Zero);
        _physics.AddBoxFixture(_body, new Vector2(0.18f, 0.18f),
            density: 1f, friction: 0f, restitution: 1f);

        _board.ShowHint("Press Space to launch");
    }

    protected override void OnUpdate(in View view)
    {
        var state = _physics.GetBodyState(_body);
        LocalTransform = LocalTransform with
        {
            Position = new Vector3(state.Position.X, state.Position.Y, 0f),
            Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitZ, state.Angle),
        };

        bool space = view.IsKeyDown(KeySpace);
        bool esc   = view.IsKeyDown(KeyEscape);
        if (esc && !_prevEsc) Environment.Exit(0);
        if (space && !_prevSpace && _awaitingLaunch) Launch();
        _prevSpace = space;
        _prevEsc   = esc;

        if (_awaitingLaunch) return;

        // Sudden X velocity flip → paddle/wall hit. No contact events on the
        // physics surface yet, so this is the proxy: we sample velocity each
        // frame and play the hit sample when its X sign flips.
        var vel = state.Velocity;
        if (Math.Sign(vel.X) != Math.Sign(_lastVelocity.X) && _lastVelocity.X != 0)
            _audio.Play(_hit, volume: 0.5f);
        _lastVelocity = vel;

        if (state.Position.X >  Field.HalfW + GoalLineMargin) Score(leftScored: true);
        if (state.Position.X < -Field.HalfW - GoalLineMargin) Score(leftScored: false);
    }

    void Launch()
    {
        _awaitingLaunch = false;
        _board.HideHint();
        float dirX = _board.Total % 2 == 0 ? 1f : -1f;
        float dirY = (Random.Shared.NextSingle() - 0.5f) * 0.6f;
        var v = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        _physics.SetBodyVelocity(_body, v);
        _lastVelocity = v;
    }

    void Score(bool leftScored)
    {
        _board.RecordGoal(leftScored);
        _audio.Play(_score, volume: 0.6f);
        _physics.SetBodyPosition(_body, Vector2.Zero);
        _physics.SetBodyVelocity(_body, Vector2.Zero);
        _lastVelocity   = Vector2.Zero;
        _awaitingLaunch = true;
        _board.ShowHint("Press Space to launch");
    }
}
