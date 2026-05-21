using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
#if DEBUG && WINDOWS
using KernelEngine.DevPlatform.Win32;
#endif

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddGlfwWindow(1280, 720, "KernelEngine — 05 Skybox & IBL (FreeLook)")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

#if DEBUG && WINDOWS
services.AddWin32DevPlatform();   // dev-only: thread names visible in debugger/profiler
#endif

using var app = new Application();

int entityCount = 0;

app.OnReady = (resources) =>
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

    var cubeHandle = resources.CreateCubemap(faceSize, cubeData);
    Console.WriteLine($"[KernelEngine] Cubemap: handle={cubeHandle} faceSize={faceSize}");

    app.Scene.AddNode(new SkyboxNode { CubemapHandle = cubeHandle }, "Skybox");
    entityCount++;

    var mirrorMat = resources.CreateMaterial(new Vector4(1f, 1f, 1f, 1f), metallic: 0.8f, roughness: 0.1f);
    app.Scene.AddNode(new MeshNode { MaterialHandle = mirrorMat }, "MirrorQuad");
    entityCount++;

    app.Scene.AddNode(new LightNode
    {
        Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)),
        Intensity = 1.5f,
    }, "Sun");
    entityCount++;

    var cam = app.Scene.AddNode(new FreeLookNode { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
    cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 4f) };
    app.ActiveWorld.ActiveCamera = cam.Entity;
    entityCount++;
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = (scene, input) =>
{
    scene.SetTonemapping(true, 1.0f, 2.2f);
    scene.ClearColor(0.05f, 0.05f, 0.05f, 1f);

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

// ── FreeLook camera — arrow keys: look, WASD: move, Shift/Ctrl: fly ──────────

sealed class FreeLookNode : CameraNode
{
    private float _speed     = 8.0f;
    private float _rotateDeg = 90.0f;
    private float _pitch     = 0f;
    private float _yaw       = 0f;

    protected override void OnUpdate(float dt)
    {
        var input = Input.Current;

        if (input.IsKeyDown(262)) _yaw   -= _rotateDeg * dt; // Right arrow
        if (input.IsKeyDown(263)) _yaw   += _rotateDeg * dt; // Left arrow
        if (input.IsKeyDown(265)) _pitch += _rotateDeg * dt; // Up arrow
        if (input.IsKeyDown(264)) _pitch -= _rotateDeg * dt; // Down arrow
        _pitch = Math.Clamp(_pitch, -89f, 89f);

        var rot     = Quaternion.CreateFromYawPitchRoll(_yaw * MathF.PI / 180f, _pitch * MathF.PI / 180f, 0f);
        var forward = Vector3.Transform(-Vector3.UnitZ, rot);
        var right   = Vector3.Transform( Vector3.UnitX, rot);

        var move = Vector3.Zero;
        if (input.IsKeyDown(87))  move += forward;  // W
        if (input.IsKeyDown(83))  move -= forward;  // S
        if (input.IsKeyDown(65))  move -= right;    // A
        if (input.IsKeyDown(68))  move += right;    // D
        if (input.IsKeyDown(340)) move += Vector3.UnitY; // Left Shift
        if (input.IsKeyDown(341)) move -= Vector3.UnitY; // Left Ctrl
        if (move != Vector3.Zero) move   = Vector3.Normalize(move);

        LocalTransform = LocalTransform with
        {
            Position = LocalTransform.Position + move * _speed * dt,
            Rotation = rot,
        };
    }
}
