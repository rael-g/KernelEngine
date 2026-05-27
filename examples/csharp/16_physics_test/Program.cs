using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render.Bgfx;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// ── 16 Physics Test ───────────────────────────────────────────────────────────
// Validates the physics pipeline (kernel ke_physics_2d → Box2D plugin → C# IPhysics2D).
// Camera at +Z looking at origin — flattens the 3D render into a side-view of XY.
//   • Space → drop a ball at random X
//   • R     → reset (destroy all balls)
//   • Escape → quit

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger().AddConsoleSink(LogLevel.Info)
    .AddInput()
    .AddGlfwWindow(960, 540, "KernelEngine — 16 Physics Test (Space drops ball, R resets)")
    .AddBgfxRenderer(System.IO.Path.Combine(AppContext.BaseDirectory, "shaders"))
    .AddBox2D();

using var app = new Application();

const float floorY     = -3f;
const float floorHalfW = 8f;
const float floorHalfH = 0.5f;

app.OnReady = async (_) =>
{
    var physics = app.Services.GetRequiredService<IPhysics2D>();

    app.Tree.AddNode(new Camera { Fov = 50f, Near = 0.1f, Far = 100f }, "Camera")
        .LocalTransform = new Transform { Position = new Vector3(0, 0, 14), Rotation = Quaternion.Identity, Scale = Vector3.One };

    app.Tree.AddNode(new DirectionalLight {
        Direction = Vector3.Normalize(new Vector3(0.3f, 1, 0.5f)),
        Color     = Vector3.One,
        Intensity = 5f,
    }, "Sun");

    var floorMat = await app.Resources.CreateMaterialAsync(new Vector4(0.4f, 0.4f, 0.45f, 1), metallic: 0, roughness: 0.9f);
    var ballMat  = await app.Resources.CreateMaterialAsync(new Vector4(0.9f, 0.3f, 0.2f, 1), metallic: 0.1f, roughness: 0.4f);
    var cubeMesh = await app.Resources.CreateMeshAsync(MeshShape.Cube());

    // Static floor: render + body.
    var floor = app.Tree.AddNode(new MeshRenderer { Mesh = cubeMesh, Material = floorMat }, "Floor");
    floor.LocalTransform = floor.LocalTransform with {
        Position = new Vector3(0, floorY, 0),
        Scale    = new Vector3(floorHalfW * 2, floorHalfH * 2, 1),
    };
    var floorBody = physics.CreateBody(BodyType2D.Static, new Vector2(0, floorY));
    physics.AddBoxFixture(floorBody, new Vector2(floorHalfW, floorHalfH), friction: 0.5f);

    app.Tree.AddNode(new PhysicsScene(app.Tree, physics, ballMat, cubeMesh), "PhysicsScene");
};

app.OnUpdate = (tree, _) => tree.ClearColor(0.08f, 0.08f, 0.12f, 1f);

app.Run(services);

// ── Behaviour ─────────────────────────────────────────────────────────────────

sealed class PhysicsScene(Tree tree, IPhysics2D physics, Material ballMat, Mesh cubeMesh) : Node
{
    private readonly List<(Node node, BodyHandle2D body)> _balls = new();

    protected override void Start()
    {
        // Initial ball so something is happening at frame 1.
        Spawn(new Vector2(0, 4));
    }

    protected override void Update(float deltaTime)
    {
        physics.Step(deltaTime);
        foreach (var (node, body) in _balls)
        {
            var s = physics.GetBodyState(body);
            node.LocalTransform = node.LocalTransform with {
                Position = new Vector3(s.Position.X, s.Position.Y, 0),
                Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitZ, s.Angle),
            };
        }
    }

    protected override void OnInput(ref InputEvent evt)
    {
        if (evt.Kind != InputEventKind.KeyDown) return;
        switch (evt.Key)
        {
            case Key.Space:
                Spawn(new Vector2((Random.Shared.NextSingle() - 0.5f) * 6f, 5f));
                break;
            case Key.R:
                Console.WriteLine($"Reset — destroying {_balls.Count} balls");
                foreach (var (node, body) in _balls)
                {
                    physics.DestroyBody(body);
                    tree.DestroyNode(node);
                }
                _balls.Clear();
                break;
            case Key.Escape:
                Environment.Exit(0);
                break;
        }
    }

    private void Spawn(Vector2 at)
    {
        var node = tree.AddNode(new MeshRenderer { Mesh = cubeMesh, Material = ballMat }, $"Ball_{_balls.Count}");
        node.LocalTransform = node.LocalTransform with { Position = new Vector3(at.X, at.Y, 0) };
        var body = physics.CreateBody(BodyType2D.Dynamic, at);
        physics.AddBoxFixture(body, new Vector2(0.5f, 0.5f), density: 1.0f, friction: 0.3f, restitution: 0.5f);
        _balls.Add((node, body));
        Console.WriteLine($"Spawned at ({at.X:F2}, {at.Y:F2}); total={_balls.Count}");
    }
}
