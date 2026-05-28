using System.Numerics;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Bgfx;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// ── Pong (2D) ─────────────────────────────────────────────────────────────────
// First complete-game example, rewritten on top of Camera2D + Sprite2D.
//   • W / S      — left paddle up / down
//   • Up / Down  — right paddle up / down
//   • Space      — launch ball (also after each score)
//   • Escape     — quit

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger().AddConsoleSink(LogLevel.Warning)
    .AddInput()
    .AddGlfwWindow(960, 540, "KernelEngine — Pong (2D)")
    .AddBgfxRenderer(System.IO.Path.Combine(AppContext.BaseDirectory, "shaders"))
    .AddBox2D(gravityX: 0f, gravityY: 0f)        // top-down: no gravity
    .AddMiniAudio();

using var app = new Application();
app.OnReady = (_) => GameSetup.BuildAsync(app);
app.OnUpdate = (tree, _) =>
{
    tree.ClearColor(0.04f, 0.04f, 0.08f, 1f);
    // Flat ambient — sprites are unlit-feeling without a real 2D shader path.
    tree.SetAmbientLight(1f, 1f, 1f);
};
app.Run(services);

// ── Field constants ──────────────────────────────────────────────────────────

static class Field
{
    public const float HalfW         = 8f;
    public const float HalfH         = 4.5f;
    public const float WallThickness = 0.25f;
}

// ── Setup ─────────────────────────────────────────────────────────────────────

static class GameSetup
{
    public static async System.Threading.Tasks.Task BuildAsync(Application app)
    {
        var physics = app.Services.GetRequiredService<IPhysics2D>();
        var audio   = app.Services.GetRequiredService<IAudio>();

        // 2D camera: orthographic, 10-unit-tall viewport (OrthographicSize = 5).
        app.Tree.AddNode(new Camera2D { OrthographicSize = 5f });

        // One shared quad mesh + per-color materials (Pong uses two: white and dark blue).
        var quadMesh = await app.Resources.CreateMeshAsync(MeshShape.Quad());
        var whiteMat = await app.Resources.CreateMaterialAsync(new Vector4(0.95f, 0.95f, 0.95f, 1));
        var wallMat  = await app.Resources.CreateMaterialAsync(new Vector4(0.15f, 0.15f, 0.2f,  1));

        // Walls (top + bottom). Static body + visual quad.
        AddWall(app, physics, quadMesh, wallMat, y: +Field.HalfH);
        AddWall(app, physics, quadMesh, wallMat, y: -Field.HalfH);

        // Physics stepper — first child so pre-order walk advances the world before paddle/ball
        // Updates read/write velocities and positions this frame.
        app.Tree.AddNode(new PhysicsStepper(physics));

        // Paddles
        app.Tree.AddNode(new Paddle(physics, x: -Field.HalfW + 0.5f, up: Key.W,  down: Key.S)    { Mesh = quadMesh, Material = whiteMat, Name = "PaddleLeft"  });
        app.Tree.AddNode(new Paddle(physics, x: +Field.HalfW - 0.5f, up: Key.Up, down: Key.Down) { Mesh = quadMesh, Material = whiteMat, Name = "PaddleRight" });

        // Audio: synth a beep and a score tone (no committed binary assets).
        var hitSfx   = audio.LoadSound(WavSynth.WriteSine(440, durationMs: 60,  filename: "ke_pong_hit"));
        var scoreSfx = audio.LoadSound(WavSynth.WriteSine(220, durationMs: 200, filename: "ke_pong_score"));

        // Ball
        app.Tree.AddNode(new Ball(physics, audio, hitSfx, scoreSfx) { Mesh = quadMesh, Material = whiteMat });
    }

    static void AddWall(Application app, IPhysics2D physics, Mesh mesh, Material mat, float y)
    {
        app.Tree.AddNode(new Sprite2D {
            Mesh       = mesh,
            Material   = mat,
            Size       = new Vector2(Field.HalfW * 2, Field.WallThickness * 2),
            Position2D = new Vector2(0, y),
            Name       = $"Wall_{y:F0}",
        });
        var body = physics.CreateBody(BodyType2D.Static, new Vector2(0, y));
        physics.AddBoxFixture(body, new Vector2(Field.HalfW, Field.WallThickness), friction: 0f, restitution: 1.0f);
    }
}

// ── Physics stepper ───────────────────────────────────────────────────────────

sealed class PhysicsStepper(IPhysics2D physics) : Node
{
    protected override void Update(float dt) => physics.Step(dt);
}

// ── Paddle ────────────────────────────────────────────────────────────────────

sealed class Paddle(IPhysics2D physics, float x, Key up, Key down) : Sprite2D
{
    const float HalfW = 0.15f;
    const float HalfH = 0.9f;
    const float Speed = 7f;

    private BodyHandle2D _body;

    protected override void Start()
    {
        // Visual: Sprite2D handles Size → Scale; we set Position2D for X (Y starts at 0).
        Size       = new Vector2(HalfW * 2, HalfH * 2);
        Position2D = new Vector2(x, 0);
        base.Start();

        _body = physics.CreateBody(BodyType2D.Kinematic, new Vector2(x, 0));
        physics.AddBoxFixture(_body, new Vector2(HalfW, HalfH), friction: 0f, restitution: 1.0f);
    }

    protected override void Update(float dt)
    {
        var input = InputContext.Current;
        float vy = 0;
        if (input.IsKeyDown(up))   vy += Speed;
        if (input.IsKeyDown(down)) vy -= Speed;
        physics.SetBodyVelocity(_body, new Vector2(0, vy));

        var s = physics.GetBodyState(_body);
        float maxY = Field.HalfH - Field.WallThickness - HalfH;
        var y = Math.Clamp(s.Position.Y, -maxY, maxY);
        if (y != s.Position.Y) physics.SetBodyPosition(_body, new Vector2(s.Position.X, y), 0);

        Position2D = new Vector2(s.Position.X, y);
    }
}

// ── Ball ──────────────────────────────────────────────────────────────────────

sealed class Ball(IPhysics2D physics, IAudio audio, SoundHandle hitSfx, SoundHandle scoreSfx) : Sprite2D
{
    const float Half         = 0.18f;
    const float InitialSpeed = 6f;

    private BodyHandle2D _body;
    private int  _scoreLeft, _scoreRight;
    private bool _awaitingLaunch = true;
    private Vector2 _lastVelocity;

    protected override void Start()
    {
        Size = new Vector2(Half * 2, Half * 2);
        base.Start();

        _body = physics.CreateBody(BodyType2D.Dynamic, Vector2.Zero);
        physics.AddBoxFixture(_body, new Vector2(Half, Half), density: 1.0f, friction: 0f, restitution: 1.0f);

        Console.WriteLine("Pong ready. Press Space to launch the ball.");
    }

    protected override void OnInput(ref InputEvent evt)
    {
        if (evt.Kind != InputEventKind.KeyDown) return;
        switch (evt.Key)
        {
            case Key.Space: if (_awaitingLaunch) Launch(); break;
            case Key.Escape: Environment.Exit(0); break;
        }
    }

    protected override void Update(float dt)
    {
        var s = physics.GetBodyState(_body);
        Position2D = s.Position;

        if (_awaitingLaunch) return;

        // Sudden X velocity flip → played the paddle/wall hit sound.
        if (Math.Sign(s.Velocity.X) != Math.Sign(_lastVelocity.X) && _lastVelocity.X != 0)
            audio.Play(hitSfx, volume: 0.5f);
        _lastVelocity = s.Velocity;

        if (s.Position.X >  Field.HalfW + 0.5f) Score(left: true);
        if (s.Position.X < -Field.HalfW - 0.5f) Score(left: false);
    }

    void Launch()
    {
        _awaitingLaunch = false;
        float dirX = (_scoreLeft + _scoreRight) % 2 == 0 ? 1 : -1;
        float dirY = (Random.Shared.NextSingle() - 0.5f) * 0.6f;
        var v = Vector2.Normalize(new Vector2(dirX, dirY)) * InitialSpeed;
        physics.SetBodyVelocity(_body, v);
        _lastVelocity = v;
    }

    void Score(bool left)
    {
        if (left) _scoreLeft++; else _scoreRight++;
        Console.WriteLine($"SCORE!  Left {_scoreLeft}  —  Right {_scoreRight}");
        audio.Play(scoreSfx, volume: 0.6f);
        physics.SetBodyPosition(_body, Vector2.Zero, 0);
        physics.SetBodyVelocity(_body, Vector2.Zero);
        _awaitingLaunch = true;
        Console.WriteLine("Press Space to launch again.");
    }
}

// ── WAV synthesis (same pattern as example 15) ────────────────────────────────

static class WavSynth
{
    public static string WriteSine(int frequency, int durationMs, string filename)
    {
        const int sampleRate = 44100;
        int numSamples = sampleRate * durationMs / 1000;
        int dataSize   = numSamples * 2;

        var path = Path.Combine(Path.GetTempPath(), $"{filename}.wav");
        using var fs = new FileStream(path, FileMode.Create, FileAccess.Write);
        using var w  = new BinaryWriter(fs);
        w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));
        w.Write(36 + dataSize);
        w.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt "));
        w.Write(16);
        w.Write((short)1);
        w.Write((short)1);
        w.Write(sampleRate);
        w.Write(sampleRate * 2);
        w.Write((short)2);
        w.Write((short)16);
        w.Write(System.Text.Encoding.ASCII.GetBytes("data"));
        w.Write(dataSize);

        double envSamples = sampleRate * 0.010;
        for (int i = 0; i < numSamples; i++)
        {
            double t = (double)i / sampleRate;
            double env = Math.Min(1.0, Math.Min(i / envSamples, (numSamples - i) / envSamples));
            short sample = (short)(env * 8000 * Math.Sin(2 * Math.PI * frequency * t));
            w.Write(sample);
        }
        return path;
    }
}
