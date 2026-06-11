using System.Diagnostics;
using System.Numerics;
using KernelEngine.Asset.Assimp;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// 13_full_scene — every stabilized feature in one scene: ground plane,
// loaded model (Box.gltf), directional + ambient + 8 orbiting point lights,
// shadows, ACES tonemapping, bloom. SSAO is requested but stays a no-op
// (Kanban Z3 — bgfx SSAO path is empty).

string modelPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../../assets/Box.gltf"));

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddAssimpAssetLoader()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 13 Full Scene"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.05f, 0.05f, 0.08f, 1.0f)))
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new ShadowModule(resolution: 1024, frustumSize: 30f, farPlane: 60f))
    .Add<IRuntimeModule>(new PostProcessModule(
        tonemapping: true, tonemappingExposure: 1.0f, tonemappingGamma: 2.2f,
        bloom:       true, bloomThreshold:      0.9f, bloomIntensity:   1.0f,
        ssao:        true, ssaoRadius:          0.5f, ssaoBias:         0.025f, ssaoStrength: 1.5f))
    .Add<IRuntimeModule>(new SceneModule((tree, sp) =>
    {
        Console.WriteLine("[KernelEngine] Example: 13_full_scene");
        Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
        Console.WriteLine("[KernelEngine] Features: shadows, hdr, bloom, ssao*, model_loading, 8_orbiting_point_lights");

        tree.AddNode(new AmbientLight { Color = new(0.02f, 0.02f, 0.02f) }, "Ambient");

        var cam     = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "MainCamera");
        var eye     = new Vector3(8f, 8f, 15f);
        var target  = new Vector3(0f, 2f, 0f);
        var lookRot = Quaternion.CreateFromRotationMatrix(
            Matrix4x4.CreateWorld(eye, Vector3.Normalize(target - eye), Vector3.UnitY));
        cam.LocalTransform = cam.LocalTransform with { Position = eye, Rotation = lookRot };

        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1f, 0.5f)),
            Color     = new Vector3(1f, 0.95f, 0.8f),
            Intensity = 4f,
        }, "Sun");

        // Floor: a Plane primitive (XZ, normal +Y) scaled out for a 50-unit ground.
        var planeMesh = MeshPrimitives.Plane(tree.Renderer);
        var floorMat  = tree.Renderer.CreateMaterial(new Vector4(0.2f, 0.2f, 0.2f, 1f), roughness: 0.9f).Value;
        var floor     = tree.AddNode(new MeshRenderer { MeshHandle = planeMesh, MaterialHandle = floorMat }, "Floor");
        floor.LocalTransform = floor.LocalTransform with { Scale = new Vector3(50f, 1f, 50f) };

        try
        {
            var loader = sp.GetRequiredService<IAssetLoader>();
            Console.WriteLine($"[KernelEngine] Loading model: {modelPath}");
            using var model = loader.LoadModel(modelPath);
            Console.WriteLine($"[KernelEngine] Model: {model.Meshes.Count} meshes, {model.Materials.Count} mats, {model.Textures.Count} textures");
            var meshNodes = tree.AddModel(model, rootName: "CenterBox");

            // Lift + scale the model. Flat hierarchy for now — apply per-node.
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
                Color       = i % 2 == 0 ? Vector3.UnitX : Vector3.UnitZ,
                Intensity   = 40f,
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
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Lights: 8p 0s 1d");
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
