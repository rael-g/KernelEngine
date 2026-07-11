using System.Diagnostics;
using System.Numerics;
using KernelEngine.Asset.Assimp;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using KernelEngine.Logger;
using KernelEngine.Render;
using KernelEngine.Asset;

// 13_full_scene — ground plane, a loaded Box.gltf, directional + ambient light,
// and 8 point lights orbiting the model. Exercises ACES tonemapping (built into
// the render-v2 pipeline) and animated node behavior via OnUpdate.

string modelPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../../assets/Box.gltf"));

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddAssimpAssetLoader()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 13 Full Scene"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new Vector4(0.05f, 0.05f, 0.08f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 13_full_scene");
        Console.WriteLine("[KernelEngine] Renderer: webgpu/render-v2");
        Console.WriteLine("[KernelEngine] Features: aces_tonemapping, model_loading, 8_orbiting_point_lights");

        tree.AddNode(new AmbientLight { Color = new(0.02f, 0.02f, 0.02f) }, "Ambient");

        var cam    = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "MainCamera");
        var eye    = new Vector3(8f, 8f, 15f);
        var target = new Vector3(0f, 2f, 0f);
        var lookRot = Quaternion.CreateFromRotationMatrix(
            Matrix4x4.CreateWorld(eye, Vector3.Normalize(target - eye), Vector3.UnitY));
        cam.LocalTransform = cam.LocalTransform with { Position = eye, Rotation = lookRot };

        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new Vector3(0.3f, -1.0f, -0.5f)),
            Color     = new Vector3(1f, 0.95f, 0.8f),
            Intensity = 4f,
        }, "Sun");

        var planeMesh = KernelEngine.Render.MeshPrimitives.Plane(resources);
        var floorMat  = resources.CreateMaterial("floor", new Vector4(0.2f, 0.2f, 0.2f, 1f), roughness: 0.9f);
        var floor     = tree.AddNode(new MeshRenderer { MeshHandle = planeMesh, MaterialHandle = floorMat }, "Floor");
        floor.LocalTransform = floor.LocalTransform with { Scale = new Vector3(50f, 1f, 50f) };

        try
        {
            var loader = sp.GetRequiredService<IAssetLoader>();
            Console.WriteLine($"[KernelEngine] Loading model: {modelPath}");
            using var model = loader.LoadModel(modelPath);
            Console.WriteLine($"[KernelEngine] Model: {model.Meshes.Count} meshes, {model.Materials.Count} mats, {model.Textures.Count} textures");
            var meshNodes = tree.AddModel(model, resources, rootName: "CenterBox");
            for (int i = 0; i < meshNodes.Count; i++)
            {
                meshNodes[i].LocalTransform = meshNodes[i].LocalTransform with
                {
                    Position = new Vector3(0f, 2f, 0f),
                    Scale    = new Vector3(2f),
                };
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[KernelEngine] WARN: model load failed: {ex.Message}");
        }

        for (int i = 0; i < 8; i++)
        {
            tree.AddNode(new OrbitingLight
            {
                Color       = i % 2 == 0 ? new Vector3(1f, 0.2f, 0.2f) : new Vector3(0.2f, 0.4f, 1f),
                Intensity   = 8f,
                Radius      = 18f,
                OrbitRadius = 5f,
                Speed       = 0.5f + i * 0.1f,
                Phase       = i * (MathF.PI / 4f),
            }, $"OrbitLight_{i}");
        }
    }));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[13_full_scene] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
int frameCount = 0;
double fpsWindowStart = 0;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;

    frameCount++;
    if (now - fpsWindowStart >= 5.0)
    {
        double fps = frameCount / (now - fpsWindowStart);
        Console.WriteLine($"[13_full_scene] FPS: {fps:F2}  Lights: 8p 1d");
        frameCount     = 0;
        fpsWindowStart = now;
    }
}

runtime.UnloadModules(sp);

Console.WriteLine("[13_full_scene] Exited cleanly.");

// ── Orbiting point light — circles the origin at fixed height ────────────────

sealed class OrbitingLight : PointLight
{
    public float OrbitRadius { get; init; } = 5f;
    public float Speed       { get; init; } = 1f;
    public float Phase       { get; init; }

    private float _time;

    protected override void OnUpdate(in View view)
    {
        _time += view.DeltaTime * Speed;
        float x = MathF.Cos(_time + Phase) * OrbitRadius;
        float z = MathF.Sin(_time + Phase) * OrbitRadius;
        LocalTransform = LocalTransform with { Position = new Vector3(x, 3f, z) };
    }
}
