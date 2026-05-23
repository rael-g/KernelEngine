using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink(LogLevel.Info)
    .AddGlfwWindow(1280, 720, "KernelEngine — 06 Shadow Map Verification")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

int entityCount = 0;

app.OnReady = async (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 06_shadow_map");
    Console.WriteLine("[KernelEngine] Features: shadow_mapping, directional_light, floor_plane, cube");

    // Directional light (Sun). Per LightNode docs, Direction is the vector pointing
    // FROM the lit surface TOWARD the light source. Sun in upper-right-back → (+x, +y, +z).
    var light = app.Scene.AddNode(
        new AnimatedSun
        {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1f, 0.5f)),
            Color = Vector3.One,
            Intensity = 10.0f,
        },
        "Sun");
    entityCount++;

    // Camera
    var cam = app.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with
    {
        Position = new Vector3(0f, 5.0f, 10.0f)
    };
    app.ActiveWorld.ActiveCamera = cam.Entity;
    entityCount++;

    // Resources via the high-level ResourceManager + MeshShape primitives — no Vertex[] / handles.
    var floorMat = await app.Resources.CreateMaterialAsync(new Vector4(0.5f, 0.5f, 0.5f, 1f), metallic: 0.0f, roughness: 0.8f);
    var cubeMat  = await app.Resources.CreateMaterialAsync(new Vector4(0.8f, 0.2f, 0.2f, 1f), metallic: 0.2f, roughness: 0.3f);
    var floorMesh = await app.Resources.CreateMeshAsync(MeshShape.Plane());  // horizontal, normal +Y
    var cubeMesh  = await app.Resources.CreateMeshAsync(MeshShape.Cube());

    // Floor.
    var floor = app.Scene.AddNode(new MeshNode { Mesh = floorMesh, Material = floorMat }, "Floor");
    floor.LocalTransform = floor.LocalTransform with { Scale = new Vector3(10f, 1f, 10f) };
    entityCount++;

    // Cube (casting shadow).
    var cube = app.Scene.AddNode(new MeshNode { Mesh = cubeMesh, Material = cubeMat }, "Caster");
    cube.LocalTransform = cube.LocalTransform with { Position = new Vector3(0f, 1f, 0f) };
    entityCount++;
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.1f, 0.1f, 0.15f, 1f);
    scene.SetAmbientLight(0.15f, 0.15f, 0.15f);

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
sealed class AnimatedSun : LightNode
{
    private float _t;

    protected override void OnUpdate(float dt)
    {
        _t += dt;
        float a = MathF.Sin(_t * 0.8f);                       // -1..1 sweep
        var dir = Vector3.Normalize(new Vector3(a * 0.8f, 1.0f, 0.5f));

        var comp = GetComponent<LightComponent>(ComponentId);
        if (comp.IsEmpty) return;
        comp[0].DirX = dir.X;
        comp[0].DirY = dir.Y;
        comp[0].DirZ = dir.Z;
    }
}
