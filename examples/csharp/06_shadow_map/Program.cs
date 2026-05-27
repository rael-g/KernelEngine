using System.Numerics;
using System.Diagnostics;
using KernelEngine.Configuration;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink(LogLevel.Info)
    .AddInput()
    .AddProjectConfig("Project.toml")
    .AddGlfwWindow()
    .AddBgfxRenderer();

using var app = new Application();

int entityCount = 0;

app.OnReady = async (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 06_shadow_map");
    Console.WriteLine("[KernelEngine] Features: shadow_mapping, directional_light, floor_plane, cube");

    // Scene structure (nodes, transforms, light/camera properties) lives in Main.scene.toml.
    // Resources (Mesh, Material) still come from code — the resource pipeline is a future slice.
    SceneLoader.Load(app.Tree, "Main.scene.toml");
    entityCount = 4;

    // Hydrate the mesh-bearing nodes with their resources by name.
    var floorMat  = await app.Resources.CreateMaterialAsync(new Vector4(0.5f, 0.5f, 0.5f, 1f), metallic: 0.0f, roughness: 0.8f);
    var cubeMat   = await app.Resources.CreateMaterialAsync(new Vector4(0.8f, 0.2f, 0.2f, 1f), metallic: 0.2f, roughness: 0.3f);
    var floorMesh = await app.Resources.CreateMeshAsync(MeshShape.Plane());
    var cubeMesh  = await app.Resources.CreateMeshAsync(MeshShape.Cube());

    Attach(app.Tree.FindNode("Floor"),  floorMesh, floorMat);
    Attach(app.Tree.FindNode("Caster"), cubeMesh,  cubeMat);

    static void Attach(Node? node, Mesh mesh, Material material)
    {
        if (node is not MeshRenderer mr)
            throw new InvalidOperationException($"Expected MeshRenderer node, got {node?.GetType().Name ?? "null"}");
        mr.Mesh = mesh;
        mr.Material = material;
    }
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = (tree, input) =>
{
    tree.ClearColor(0.1f, 0.1f, 0.15f, 1f);
    tree.SetAmbientLight(0.15f, 0.15f, 0.15f);

    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Entities: {entityCount}");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);

// ── Helpers ──────────────────────────────────────────────────────────────────

/// <summary>
/// Directional light that sweeps its azimuth back and forth over time, so the cube's shadow
/// slides across the floor — a visual check that the shadow projection tracks the light.
/// </summary>
sealed class AnimatedSun : DirectionalLight
{
    private float _t;

    protected override void Update(float dt)
    {
        _t += dt;
        float a = MathF.Sin(_t * 0.8f);                       // -1..1 sweep
        Direction = Vector3.Normalize(new Vector3(a * 0.8f, 1.0f, 0.5f));
    }
}
