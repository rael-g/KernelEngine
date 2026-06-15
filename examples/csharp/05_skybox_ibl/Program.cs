using System.Diagnostics;
using System.Numerics;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Runtime;
using KernelEngine.TaskScheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// 05_skybox_ibl â€” procedural cubemap as both the visible skybox and the IBL
// environment for a metallic quad. A free-look camera (arrow keys to rotate,
// WASD/Shift/Ctrl to translate) lets you fly around to see the cubemap from
// every face and watch the IBL response on the metal surface.

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .Add<IEcs, FlecsEcs>()
    .Add<ITaskScheduler, EnkiTaskScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine â€” 05 Skybox & IBL (FreeLook)"))
    .Add<IRuntimeModule>(new BgfxRenderModule(
        shaderPath: Path.Combine(AppContext.BaseDirectory, "shaders"),
        vsync:      true,
        clearColor: (0.05f, 0.05f, 0.05f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneRenderModule())
    .Add<IRuntimeModule>(new SceneModule((tree, sp) =>
    {
        var renderer = sp.GetRequiredService<IRenderer>();
        Console.WriteLine("[KernelEngine] Example: 05_skybox_ibl");
        Console.WriteLine("[KernelEngine] Renderer: bgfx/Vulkan");
        Console.WriteLine("[KernelEngine] Features: skybox_cubemap, ibl_env_map, pbr_ggx, freelook_camera");

        // ACES tonemapping is stateful on the renderer; setting it once at
        // scene setup is enough â€” the legacy example called it per-frame
        // defensively, but the underlying state survives.
        renderer.SetTonemapping(true, 1.0f, 2.2f);

        // Procedural cubemap â€” one solid color per face for face identification.
        const uint faceSize = 64;
        var cubeData = new byte[faceSize * faceSize * 4 * 6];
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

        var cubemap = renderer.CreateCubemap(faceSize, cubeData).Value;
        Console.WriteLine($"[KernelEngine] Cubemap: handle={cubemap.Value} faceSize={faceSize}");

        tree.AddNode(new Skybox { CubemapHandle = cubemap }, "Skybox");

        var mirrorMat = renderer.CreateMaterial(Vector4.One, metallic: 0.8f, roughness: 0.1f).Value;
        tree.AddNode(new MeshRenderer { MaterialHandle = mirrorMat }, "MirrorQuad");

        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)),
            Intensity = 1.5f,
        }, "Sun");

        var cam = tree.AddNode(new FreeLook { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 4f) };
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[05_skybox_ibl] Loop running. Arrows = look, WASD = move, Shift/Ctrl = up/down. Close window to exit.");

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
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Lights: 0p 0s 1d");
        frameCount     = 0;
        fpsWindowStart = now;
    }
}

runtime.UnloadModules(sp);

Console.WriteLine("[05_skybox_ibl] Exited cleanly.");

// â”€â”€ FreeLook camera â€” arrow keys: look, WASD: move, Shift/Ctrl: fly â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

sealed class FreeLook : Camera
{
    private const float MoveSpeed   = 8.0f;
    private const float RotateDeg   = 90.0f;

    private float _pitch;
    private float _yaw;

    protected override void OnUpdate(in View view)
    {
        float dt = view.DeltaTime;

        if (view.IsKeyDown(262)) _yaw   -= RotateDeg * dt; // Right arrow
        if (view.IsKeyDown(263)) _yaw   += RotateDeg * dt; // Left arrow
        if (view.IsKeyDown(265)) _pitch += RotateDeg * dt; // Up arrow
        if (view.IsKeyDown(264)) _pitch -= RotateDeg * dt; // Down arrow
        _pitch = Math.Clamp(_pitch, -89f, 89f);

        var rot     = Quaternion.CreateFromYawPitchRoll(_yaw * MathF.PI / 180f, _pitch * MathF.PI / 180f, 0f);
        var forward = Vector3.Transform(-Vector3.UnitZ, rot);
        var right   = Vector3.Transform( Vector3.UnitX, rot);

        var move = Vector3.Zero;
        if (view.IsKeyDown(87))  move += forward;        // W
        if (view.IsKeyDown(83))  move -= forward;        // S
        if (view.IsKeyDown(65))  move -= right;          // A
        if (view.IsKeyDown(68))  move += right;          // D
        if (view.IsKeyDown(340)) move += Vector3.UnitY;  // Left Shift
        if (view.IsKeyDown(341)) move -= Vector3.UnitY;  // Left Ctrl
        if (move != Vector3.Zero) move = Vector3.Normalize(move);

        LocalTransform = LocalTransform with
        {
            Position = LocalTransform.Position + move * MoveSpeed * dt,
            Rotation = rot,
        };
    }
}
