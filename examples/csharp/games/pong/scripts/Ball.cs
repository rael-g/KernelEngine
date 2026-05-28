using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// The ball. Owns its own scoring state and reacts to <c>Launch</c>/<c>Quit</c> action events.
/// Sound effects come from child <see cref="AudioPlayer"/> nodes declared in <c>Ball.scene</c>.
/// </summary>
public sealed class Ball : DynamicBody2D
{
    const float InitialSpeed = 6f;

    private AudioPlayer? _hit;
    private AudioPlayer? _score;
    private int  _scoreLeft, _scoreRight;
    private bool _awaitingLaunch = true;
    private Vector2 _lastVelocity;

    protected override void Start()
    {
        base.Start();
        _hit   = GetNode<AudioPlayer>("HitSound");
        _score = GetNode<AudioPlayer>("ScoreSound");
        Console.WriteLine("Pong ready. Press Space to launch the ball.");
    }

    protected override void OnInputAction(ref InputActionEvent evt)
    {
        if (evt.Phase != ActionPhase.Started) return;
        if (evt.Is(PongAction.Launch) && _awaitingLaunch) Launch();
        else if (evt.Is(PongAction.Quit)) Environment.Exit(0);
    }

    protected override void Update(float dt)
    {
        var pos = Position;
        var vel = LinearVelocity;

        if (_awaitingLaunch) return;

        // Sudden X velocity flip → paddle/wall hit (no collision events in F2 MVP).
        if (Math.Sign(vel.X) != Math.Sign(_lastVelocity.X) && _lastVelocity.X != 0)
            _hit?.Play();
        _lastVelocity = vel;

        if (pos.X >  Field.HalfW + 0.5f) Score(left: true);
        if (pos.X < -Field.HalfW - 0.5f) Score(left: false);
    }

    void Launch()
    {
        _awaitingLaunch = false;
        float dirX = (_scoreLeft + _scoreRight) % 2 == 0 ? 1 : -1;
        float dirY = (Random.Shared.NextSingle() - 0.5f) * 0.6f;
        LinearVelocity = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        _lastVelocity  = LinearVelocity;
    }

    void Score(bool left)
    {
        if (left) _scoreLeft++; else _scoreRight++;
        Console.WriteLine($"SCORE!  Left {_scoreLeft}  —  Right {_scoreRight}");
        _score?.Play();
        Teleport(Vector2.Zero);
        LinearVelocity = Vector2.Zero;
        _awaitingLaunch = true;
        Console.WriteLine("Press Space to launch again.");
    }
}
