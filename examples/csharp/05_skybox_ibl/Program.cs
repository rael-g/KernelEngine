using System.Diagnostics;
using System.Numerics;

using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Input;
using KernelEngine.Io.Pool;
using KernelEngine.Logger;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;

using KernelEngine.Framework.Native;

using InputAction = KernelEngine.Framework.InputAction;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddSingleton(_ =>
    {
        var actions = new InputActions();
        var fly = actions.AddMap("Fly", 0);
        actions.BindKeyQuad(actions.AddAction(fly, "Look", NativeActionType.Axis2d), Key.Up, Key.Down, Key.Left, Key.Right);
        actions.BindKeyQuad(actions.AddAction(fly, "Move", NativeActionType.Axis2d), Key.W, Key.S, Key.A, Key.D);
        actions.BindKeyPair(actions.AddAction(fly, "Rise", NativeActionType.Axis1d), Key.ControlLeft, Key.ShiftLeft);
        return actions;
    })
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .Add<IRuntime, Runtime>()
    .AddConfig(new GlfwWindowConfig { Title = "KernelEngine — 05 Skybox & IBL (FreeLook)", Width = 1280, Height = 720 })
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .AddConfig(new DefaultRenderServiceConfig { ShaderDir = ExamplePaths.ShaderDir, ClearColor = new Vector4(0.05f, 0.05f, 0.05f, 1.0f) })
    .Add<IRuntimeModule>(new WebgpuRenderModule())
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderService>();
        Console.WriteLine("[KernelEngine] Example: 05_skybox_ibl");
        Console.WriteLine("[KernelEngine] Features: skybox_cubemap, ibl_env_map, pbr_ggx, freelook_camera");

        const uint faceSize = 64;
        var faces = new byte[faceSize * faceSize * 4 * 6];
        (byte R, byte G, byte B)[] colors =
        [
            (255, 0,   0),
            (0,   255, 255),
            (0,   255, 0),
            (255, 0,   255),
            (0,   0,   255),
            (255, 255, 0),
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

        const string quad = "quad";
        var mirrorMat = resources.CreateMaterial("mirror", Vector4.One, metallic: 0.8f, roughness: 0.1f);
        tree.AddNode(new MeshRenderer { Mesh = quad, MaterialHandle = mirrorMat }, "MirrorQuad");

        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)),
            Intensity = 1.5f,
        }, "Sun");

        var cam = tree.AddNode(new FreeLook { Fov = 60f, NearPlane = 0.1f, FarPlane = 1000f }, "Camera");
        cam.Position = new Vector3(0f, 0f, 4f);
    }));

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[05_skybox_ibl] Loop running. Arrows = look, WASD = move, Shift/Ctrl = up/down. Close window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    window.PollEvents();
    runtime.Tick((float)(now - prev));
    prev = now;
}
runtime.UnloadModules();


Console.WriteLine("[05_skybox_ibl] Exited cleanly.");

sealed class FreeLook : Camera
{
    private const float MoveSpeed = 8.0f;
    private const float RotateDeg = 90.0f;

    private float _pitch;
    private float _yaw;

    protected override bool HasBehavior => true;

    protected override void OnUpdate(in View view)
    {
        float dt = view.DeltaTime;

        var look = new InputAction(this, "Look").Vector;
        _yaw -= look.X * RotateDeg * dt;
        _pitch += look.Y * RotateDeg * dt;
        _pitch = Math.Clamp(_pitch, -89f, 89f);

        var rot = Quaternion.CreateFromYawPitchRoll(_yaw * MathF.PI / 180f, _pitch * MathF.PI / 180f, 0f);
        var forward = Vector3.Transform(-Vector3.UnitZ, rot);
        var right = Vector3.Transform(-Vector3.UnitX, rot);

        var move = Vector3.Zero;
        var walk = new InputAction(this, "Move").Vector;
        move += forward * walk.Y + right * walk.X;
        move += Vector3.UnitY * new InputAction(this, "Rise").Axis;
        if (move != Vector3.Zero) move = Vector3.Normalize(move);

        Position += move * MoveSpeed * dt;
        Rotation = rot;
    }
}
