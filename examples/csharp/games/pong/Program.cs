using System.Numerics;
using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Text.StbTrueType;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using Pong;

// Pong — hand-wired port to the new KernelEngine.Framework. Everything that
// the legacy version got from Project / .scene / .input files is materialized
// inline here as `tree.AddNode(...)` + raw key polling. The legacy autoconfig
// pipeline (Project loader, action map, scene loader, audio framework
// wrapper, scene hierarchy) is the proper workflow story — tracked as Kanban
// Z5 — and this file is what every step of that pipeline will eventually
// generate. Keeping a hand-wired reference helps validate the generators
// against a known-good runtime shape.

const float HalfW         = 8f;
const float HalfH         = 4.5f;
const float WallThickness = 0.25f;

var services = new ServiceCollection()
    .AddKernel()
    .AddProjectConfig()                          // Reads `Project` next to the exe
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddBox2D()                                  // pulls runtime.physics_2d.gravity_* from Project
    .AddMiniAudio()
    .AddTextStbTrueType()
    .AddInputActions<PongAction>()               // loads actions.input next to the exe
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule())  // pulls runtime.window from Project
    .Add<IRuntimeModule>(new BgfxRenderModule())  // pulls runtime.renderer + [render] from Project
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new SceneModule((tree, sp) =>
    {
        Console.WriteLine("[Pong] Loading…");

        var physics    = sp.GetRequiredService<IPhysics2D>();
        var audio      = sp.GetRequiredService<IAudio>();
        var fontLoader = sp.GetRequiredService<IFontLoader>();
        var actions    = sp.GetRequiredService<IInputActionMap<PongAction>>();

        // Materials — pong uses unlit-feeling colors; tonemap stays off, so
        // base colors land directly on screen.
        var whiteMat = tree.Renderer.CreateMaterial(new Vector4(0.95f, 0.95f, 0.95f, 1f), roughness: 1f).Value;
        var wallMat  = tree.Renderer.CreateMaterial(new Vector4(0.15f, 0.15f, 0.20f, 1f), roughness: 1f).Value;

        // Ambient at full white so the unlit-feeling colors above land at face
        // value through the lighting model (no directional light in this scene).
        tree.AddNode(new AmbientLight { Color = Vector3.One }, "Ambient");

        // Camera: orthographic, half-height 5, looking at origin from +Z.
        var cam = tree.AddNode(
            new Camera { Orthographic = true, OrthographicSize = 5f, Near = 0.1f, Far = 100f },
            "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 10f) };

        // Sounds.
        var assetsDir = Path.Combine(AppContext.BaseDirectory, "assets", "sounds");
        var hitSound  = audio.LoadSound(Path.Combine(assetsDir, "hit.wav"));
        var scoreSnd  = audio.LoadSound(Path.Combine(assetsDir, "score.wav"));

        // Top + bottom walls — static bodies + flat dark quads.
        SpawnWall(tree, physics, wallMat, new Vector2(0,  HalfH), HalfW, WallThickness, name: "WallTop");
        SpawnWall(tree, physics, wallMat, new Vector2(0, -HalfH), HalfW, WallThickness, name: "WallBottom");

        // Scoreboard (3 labels, score state, owns hint).
        var scoreboard = tree.AddNode(new Scoreboard(tree, fontLoader, fontSize: 56f), "Scoreboard");

        // Paddles — kinematic bodies driven by the actions.input bindings.
        tree.AddNode(new Paddle(physics, actions, whiteMat, new Vector2(-7.5f, 0f), PongAction.PaddleLeftMove ), "PaddleLeft");
        tree.AddNode(new Paddle(physics, actions, whiteMat, new Vector2( 7.5f, 0f), PongAction.PaddleRightMove), "PaddleRight");

        // Ball — dynamic body + visual + hit/score sound effects + scoring.
        tree.AddNode(new Ball(tree, physics, actions, whiteMat, audio, hitSound, scoreSnd, scoreboard), "Ball");

        // Driver — single behavior that pumps physics ONCE per frame, before
        // any per-body OnUpdate runs. Behavior list is iterated in registration
        // order; PhysicsDriver was added LAST so it runs last and reads the
        // already-applied paddle velocities. Move it FIRST to step before
        // paddles/ball read body state.
        tree.AddNode(new PhysicsDriver(physics), "PhysicsDriver");

        Console.WriteLine("[Pong] Loaded — W/S left paddle, Up/Down right, Space launch, Esc quit");
    }));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

var clock = System.Diagnostics.Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

// ── Scene factory helpers ────────────────────────────────────────────────────

static void SpawnWall(Tree tree, IPhysics2D physics, MaterialHandle mat,
                       Vector2 pos, float halfW, float halfH, string name)
{
    var node = tree.AddNode(new MeshRenderer { MaterialHandle = mat }, name);
    node.LocalTransform = node.LocalTransform with
    {
        Position = new Vector3(pos.X, pos.Y, 0f),
        Scale    = new Vector3(halfW * 2f, halfH * 2f, 1f),
    };
    var body = physics.CreateBody(BodyType2D.Static, pos);
    physics.AddBoxFixture(body, new Vector2(halfW, halfH), restitution: 1f);
}

