using System.Numerics;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Bgfx;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// ── Pong (2D) ─────────────────────────────────────────────────────────────────
// First complete-game example, fully scene-driven.
//   • W / S      — left paddle up / down
//   • Up / Down  — right paddle up / down
//   • Space      — launch ball (also after each score)
//   • Escape     — quit
//
// Program.cs only wires services. The world is declared in Main.scene; bindings in actions.input;
// clear color + ambient in the Project file. Paddle/Ball below are the only behavior glue.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger().AddConsoleSink(LogLevel.Warning)
    .AddInput()
    .AddProjectConfig()
    .AddInputActions<PongAction>()
    .AddGlfwWindow()                             // size/title come from Project [runtime.window]
    .AddBgfxRenderer()                           // shader path from Project [runtime.renderer]
    .AddBox2D(gravityX: 0f, gravityY: 0f)
    .AddMiniAudio()
    .AddAudioFramework()
    ;

using var app = new Application();
app.Run(services);

// ── Action enum ──────────────────────────────────────────────────────────────

public enum PongAction
{
    PaddleLeftMove,    // Axis1D: -1 = down, +1 = up
    PaddleRightMove,   // Axis1D
    Launch,            // Button
    Quit,              // Button
}

// ── Field constants (used by Paddle clamp + Ball scoring zone) ───────────────

static class Field
{
    public const float HalfW         = 8f;
    public const float HalfH         = 4.5f;
    public const float WallThickness = 0.25f;
}

// ── Paddle ────────────────────────────────────────────────────────────────────
// Instantiated by SceneLoader; ctor-injects IInputActionReader<PongAction>.
// MoveAction is set per-instance from the scene file (PaddleLeftMove / PaddleRightMove).

namespace Pong
{
    public sealed class Paddle(IInputActionReader<PongAction> actions) : KinematicBody2D
    {
        const float HalfH = 0.9f;
        const float Speed = 7f;

        public PongAction MoveAction { get; set; }

        protected override void Update(float dt)
        {
            float vy = actions.GetActionAxis1D(MoveAction) * Speed;

            // Velocity clamp at the boundaries — refuse motion that would leave the play area
            // (avoids the 1-frame overshoot of position-clamping with a fixed-step physics loop).
            var pos = Position;
            float maxY = Field.HalfH - Field.WallThickness - HalfH;
            if (vy > 0 && pos.Y >= maxY) vy = 0;
            if (vy < 0 && pos.Y <= -maxY) vy = 0;

            LinearVelocity = new Vector2(0, vy);
        }
    }

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
}
