using System.Diagnostics;
using System.Numerics;
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
using KernelEngine.Input;

// 05_skybox_ibl — a procedural cubemap as both the visible skybox and the IBL
// environment for a metallic quad. Render v2 (webgpu): the skybox is drawn in
// the forward pass and the forward IBL samples the same cubemap (direct env
// sampling; split-sum is deferred debt). A free-look camera (arrows = look,
// WASD/Shift/Ctrl = move) flies around to see every face + the IBL response.

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 05 Skybox & IBL (FreeLook)"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new Vector4(0.05f, 0.05f, 0.05f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 05_skybox_ibl");
        Console.WriteLine("[KernelEngine] Features: skybox_cubemap, ibl_env_map, pbr_ggx, freelook_camera");

        // Procedural cubemap — one solid color per face (+X,-X,+Y,-Y,+Z,-Z).
        const uint faceSize = 64;
        var faces = new byte[faceSize * faceSize * 4 * 6];
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
                faces[off + i * 4 + 0] = colors[f].R;
                faces[off + i * 4 + 1] = colors[f].G;
                faces[off + i * 4 + 2] = colors[f].B;
                faces[off + i * 4 + 3] = 255;
            }
        }
        var cubemap = resources.UploadCubemap("sky_cubemap", faceSize, faces);

        tree.AddNode(new Skybox { CubemapHandle = cubemap }, "Skybox");

        var quad      = KernelEngine.Render.MeshPrimitives.Quad(resources);
        var mirrorMat = resources.CreateMaterial("mirror", Vector4.One, metallic: 0.8f, roughness: 0.1f);
        tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = mirrorMat }, "MirrorQuad");

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
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[05_skybox_ibl] Exited cleanly.");

// ── FreeLook camera — arrows: look, WASD: move, Shift/Ctrl: fly ──────────────

sealed class FreeLook : Camera
{
    private const float MoveSpeed = 8.0f;
    private const float RotateDeg = 90.0f;

    private float _pitch;
    private float _yaw;

    protected override void OnUpdate(in View view)
    {
        float dt = view.DeltaTime;

        // The engine's camera looks down local −Z with a left-handed view, so its
        // right axis is −localX (cross(up, forward)). Yaw therefore increases to
        // the right and the strafe axis is −UnitX — matching what the view shows.
        if (view.IsKeyDown(262)) _yaw   += RotateDeg * dt; // Right arrow
        if (view.IsKeyDown(263)) _yaw   -= RotateDeg * dt; // Left arrow
        if (view.IsKeyDown(265)) _pitch += RotateDeg * dt; // Up arrow
        if (view.IsKeyDown(264)) _pitch -= RotateDeg * dt; // Down arrow
        _pitch = Math.Clamp(_pitch, -89f, 89f);

        var rot     = Quaternion.CreateFromYawPitchRoll(_yaw * MathF.PI / 180f, _pitch * MathF.PI / 180f, 0f);
        var forward = Vector3.Transform(-Vector3.UnitZ, rot);
        var right   = Vector3.Transform(-Vector3.UnitX, rot);

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
