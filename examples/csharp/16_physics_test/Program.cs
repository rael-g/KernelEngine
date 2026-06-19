using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// 16_physics_test — kernel ke_physics_2d → Box2D plugin → IPhysics2D. Camera
// at +Z looking at origin flattens the 3D scene into a 2D side-view. Cubes
// drop onto a static floor and bounce.
//   • Space → spawn a cube at a random X
//   • R     → destroy every spawned cube + reset
//   • Esc   → quit

const float FloorY     = -3f;
const float FloorHalfW = 8f;
const float FloorHalfH = 0.5f;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddBox2D()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(960, 540, "KernelEngine — 16 Physics Test (Space drops cube, R resets)"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.08f, 0.08f, 0.12f, 1.0f)))
        .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new SceneModule((tree, sp) =>
    {
        var renderer = sp.GetRequiredService<IRenderer>();
        Console.WriteLine("[KernelEngine] Example: 16_physics_test");
        Console.WriteLine("[KernelEngine] Features: box2d, dynamic_bodies, spawn_and_reset");

        var physics = sp.GetRequiredService<IPhysics2D>();

        var cam = tree.AddNode(new Camera { Fov = 50f, Near = 0.1f, Far = 100f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 14f) };

        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new Vector3(0.3f, 1f, 0.5f)),
            Color     = Vector3.One,
            Intensity = 5f,
        }, "Sun");

        var cubeMesh = MeshPrimitives.Cube(renderer);
        var floorMat = renderer.CreateMaterial(new Vector4(0.4f, 0.4f, 0.45f, 1f), roughness: 0.9f).Value;
        var ballMat  = renderer.CreateMaterial(new Vector4(0.9f, 0.3f, 0.2f, 1f), metallic: 0.1f, roughness: 0.4f).Value;

        var floor = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = floorMat }, "Floor");
        floor.LocalTransform = floor.LocalTransform with
        {
            Position = new Vector3(0f, FloorY, 0f),
            Scale    = new Vector3(FloorHalfW * 2f, FloorHalfH * 2f, 1f),
        };
        var floorBody = physics.CreateBody(BodyType2D.Static, new Vector2(0f, FloorY));
        physics.AddBoxFixture(floorBody, new Vector2(FloorHalfW, FloorHalfH), friction: 0.5f);

        tree.AddNode(new PhysicsScene(physics, cubeMesh, ballMat), "PhysicsScene");
    }));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[16_physics_test] Loop running. Close the window to exit.");

var clock = System.Diagnostics.Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[16_physics_test] Exited cleanly.");

// ── PhysicsScene — drives the simulation + spawns/destroys balls on input ────

sealed class PhysicsScene : Node
{
    private const int KeySpace  = 32;
    private const int KeyR      = 82;
    private const int KeyEscape = 256;

    private readonly IPhysics2D     _physics;
    private readonly MeshHandle     _ballMesh;
    private readonly MaterialHandle _ballMat;
    private readonly List<(Node Node, BodyHandle2D Body)> _balls = new();

    private bool _prevSpace;
    private bool _prevR;
    private bool _prevEsc;
    private bool _initialDropped;

    public PhysicsScene(IPhysics2D physics, MeshHandle ballMesh, MaterialHandle ballMat)
    {
        _physics  = physics;
        _ballMesh = ballMesh;
        _ballMat  = ballMat;
    }

    protected override void OnBind(NodeWorld nodeWorld) { }

    protected override void OnUpdate(in View view)
    {
        if (!_initialDropped)
        {
            // First-frame drop so something is happening before any input.
            Spawn(new Vector2(0f, 4f));
            _initialDropped = true;
        }

        _physics.Step(view.DeltaTime);

        for (int i = 0; i < _balls.Count; i++)
        {
            var (node, body) = _balls[i];
            var s            = _physics.GetBodyState(body);
            node.LocalTransform = node.LocalTransform with
            {
                Position = new Vector3(s.Position.X, s.Position.Y, 0f),
                Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitZ, s.Angle),
            };
        }

        bool space = view.IsKeyDown(KeySpace);
        bool r     = view.IsKeyDown(KeyR);
        bool esc   = view.IsKeyDown(KeyEscape);

        if (space && !_prevSpace)
            Spawn(new Vector2((Random.Shared.NextSingle() - 0.5f) * 6f, 5f));

        if (r && !_prevR)
        {
            Console.WriteLine($"Reset — destroying {_balls.Count} balls");
            for (int i = 0; i < _balls.Count; i++)
            {
                _physics.DestroyBody(_balls[i].Body);
                NodeWorld!.DestroyNode(_balls[i].Node);
            }
            _balls.Clear();
        }

        if (esc && !_prevEsc) Environment.Exit(0);

        _prevSpace = space;
        _prevR     = r;
        _prevEsc   = esc;
    }

    private void Spawn(Vector2 at)
    {
        var node = NodeWorld!.AddNode(
            new MeshRenderer { MeshHandle = _ballMesh, MaterialHandle = _ballMat },
            $"Ball_{_balls.Count}");
        node.LocalTransform = node.LocalTransform with { Position = new Vector3(at.X, at.Y, 0f) };

        var body = _physics.CreateBody(BodyType2D.Dynamic, at);
        _physics.AddBoxFixture(body, new Vector2(0.5f, 0.5f), density: 1f, friction: 0.3f, restitution: 0.5f);

        _balls.Add((node, body));
        Console.WriteLine($"Spawned at ({at.X:F2}, {at.Y:F2}); total={_balls.Count}");
    }
}
