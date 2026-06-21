using System.Numerics;

namespace Pong;

/// <summary>
/// The ball. Owns its own scoring state and reacts to <c>Launch</c>/<c>Quit</c> action events.
/// Sound effects come from child <see cref="AudioPlayer"/> nodes declared in <c>Ball.scene</c>.
/// </summary>
public sealed class Ball : DynamicBody2D
{
    const float InitialSpeed = 6f;

    // Margin past the play-area edge before counting a goal — gives the ball a moment to leave
    // the screen before the score animation fires.
    const float GoalLineMargin = 0.5f;

    private AudioPlayer _hit       = null!;
    private AudioPlayer _score     = null!;
    private Scoreboard  _board     = null!;
    private bool        _awaitingLaunch = true;
    private Vector2     _lastVelocity;

    protected override void Start()
    {
        base.Start();
        _hit   = GetNode<AudioPlayer>("HitSound")
                 ?? throw new InvalidOperationException("Ball requires a HitSound AudioPlayer child.");
        _score = GetNode<AudioPlayer>("ScoreSound")
                 ?? throw new InvalidOperationException("Ball requires a ScoreSound AudioPlayer child.");
        _board = GetNode<Scoreboard>("../Scoreboard")
                 ?? throw new InvalidOperationException("Ball requires a sibling Scoreboard node at '/Scoreboard'.");
        _board.ShowHint("Press Space to launch");
    }

    protected override void OnInputAction(ref InputActionEvent evt)
    {
        if (evt.Phase != ActionPhase.Started) return;
        if (evt.Is(PongAction.Launch) && _awaitingLaunch) Launch();
        // Quit lives here for lack of a dedicated menu/system node in this MVP example —
        // a real game would route Quit through a UIInputRouter or similar instead.
        else if (evt.Is(PongAction.Quit)) Environment.Exit(0);
    }

    protected override void Update(float dt)
    {
        var pos = Position;
        var vel = LinearVelocity;

        if (_awaitingLaunch) return;

        // Sudden X velocity flip → paddle/wall hit (no collision events in F2 MVP).
        if (Math.Sign(vel.X) != Math.Sign(_lastVelocity.X) && _lastVelocity.X != 0)
            _hit.Play();
        _lastVelocity = vel;

        if (pos.X >  Field.HalfW + GoalLineMargin) Score(leftSide: true);
        if (pos.X < -Field.HalfW - GoalLineMargin) Score(leftSide: false);
    }

    void Launch()
    {
        _awaitingLaunch = false;
        _board.HideHint();
        // Alternate launch direction by total goals so neither side gets repeated free balls.
        float dirX = _board.Total % 2 == 0 ? 1 : -1;
        float dirY = (Random.Shared.NextSingle() - 0.5f) * 0.6f;
        LinearVelocity = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        _lastVelocity  = LinearVelocity;
    }

    void Score(bool leftSide)
    {
        _board.RecordGoal(leftSide);
        _score.Play();
        Teleport(Vector2.Zero);
        LinearVelocity = Vector2.Zero;
        _awaitingLaunch = true;
        _board.ShowHint("Press Space to launch");
    }
}
