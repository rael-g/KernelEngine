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
    .AddConsoleSink()
    .AddMessagePipe()
    .AddGlfwWindow(1280, 720, "KernelEngine — 05 Skybox & IBL")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

int entityCount = 0;

app.OnReady = () =>
{
    Console.WriteLine("[KernelEngine] Example: 05_skybox_ibl");
    Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
    Console.WriteLine("[KernelEngine] Features: skybox_cubemap, ibl_env_map, pbr_ggx, orbiting_camera");

    // Procedural cubemap — one solid color per face
    uint faceSize = 64;
    byte[] cubeData = new byte[faceSize * faceSize * 4 * 6];
    (byte R, byte G, byte B)[] colors =
    [
        (255, 0,   0),   // +X Red
        (0,   255, 255), // -X Cyan
        (0,   255, 0),   // +Y Green
        (255, 0,   255), // -Y Magenta
        (0,   0,   255), // +Z Blue
        (255, 255, 0),   // -Z Yellow
    ];
    for (int f = 0; f < 6; f++)
    {
        int off = f * (int)(faceSize * faceSize * 4);
        for (int i = 0; i < faceSize * faceSize; i++)
        {
            cubeData[off + i * 4 + 0] = colors[f].R;
            cubeData[off + i * 4 + 1] = colors[f].G;
            cubeData[off + i * 4 + 2] = colors[f].B;
            cubeData[off + i * 4 + 3] = 255;
        }
    }

    var cubeHandle = app.Renderer.CreateCubemap(faceSize, cubeData).Value;
    Console.WriteLine($"[KernelEngine] Cubemap: handle={cubeHandle} faceSize={faceSize}");

    app.ActiveWorld.Scene.AddNode(new SkyboxNode { CubemapHandle = cubeHandle }, "Skybox");
    entityCount++;

    var mirrorMat = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: 0.8f, roughness: 0.1f).Value;
    app.ActiveWorld.Scene.AddNode(new MeshNode { MaterialHandle = mirrorMat }, "MirrorQuad");
    entityCount++;

    app.ActiveWorld.Scene.AddNode(new LightNode
    {
        Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)),
        Intensity = 1.5f,
    }, "Sun");
    entityCount++;

    app.Renderer.SetTonemapping(true, 1.0f, 2.2f);

    var cam = app.ActiveWorld.Scene.AddNode(new OrbitingCameraNode { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
    app.ActiveWorld.ActiveCamera = cam.Entity;
    entityCount++;
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = () =>
{
    var res = app.Renderer.ClearColor(0.05f, 0.05f, 0.05f, 1f);
    KernelException.ThrowIfFailed(res, nameof(app.Renderer.ClearColor));

    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Entities: {entityCount}  Lights: 0p 0s 1d");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);

// ── Orbiting camera ───────────────────────────────────────────────────────────

sealed class OrbitingCameraNode : CameraNode
{
    private float _angle = 0f;
    private const float Radius   = 4f;
    private const float Height   = 1.5f;
    private const float SpeedDeg = 30f; // degrees per second

    protected override void OnUpdate(float dt)
    {
        _angle += SpeedDeg * dt * MathF.PI / 180f;
        var pos = new Vector3(MathF.Sin(_angle) * Radius, Height, MathF.Cos(_angle) * Radius);
        var forward = Vector3.Normalize(-pos);
        var right   = Vector3.Normalize(Vector3.Cross(forward, Vector3.UnitY));
        var up      = Vector3.Cross(right, forward);
        var rot     = Quaternion.CreateFromRotationMatrix(new Matrix4x4(
            right.X,   right.Y,   right.Z,   0,
            up.X,      up.Y,      up.Z,      0,
           -forward.X,-forward.Y,-forward.Z, 0,
            0,         0,         0,         1));
        LocalTransform = LocalTransform with { Position = pos, Rotation = rot };
    }
}
