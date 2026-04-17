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
    .AddInput()
    .AddGlfwWindow(1280, 720, "KernelEngine — 05 Skybox & IBL (FreeLook)")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

app.OnReady = () =>
{
    // ── Generate Procedural Cubemap ────────────────────────────────────────
    uint faceSize = 64;
    byte[] cubeData = new byte[faceSize * faceSize * 4 * 6];
    var colors = new (byte R, byte G, byte B)[]
    {
        (255, 0, 0),   // +X: Red
        (0, 255, 255), // -X: Cyan
        (0, 255, 0),   // +Y: Green
        (255, 0, 255), // -Y: Magenta
        (0, 0, 255),   // +Z: Blue
        (255, 255, 0)  // -Z: Yellow
    };

    for (int f = 0; f < 6; f++)
    {
        int faceOffset = f * (int)(faceSize * faceSize * 4);
        for (int i = 0; i < faceSize * faceSize; i++)
        {
            cubeData[faceOffset + i * 4 + 0] = colors[f].R;
            cubeData[faceOffset + i * 4 + 1] = colors[f].G;
            cubeData[faceOffset + i * 4 + 2] = colors[f].B;
            cubeData[faceOffset + i * 4 + 3] = 255;
        }
    }

    var cubeHandle = app.Renderer.CreateCubemap(faceSize, cubeData).Value;
    app.ActiveWorld.Scene.AddNode(new SkyboxNode { CubemapHandle = cubeHandle }, "Skybox");

    var mirrorMat = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: 1.0f, roughness: 0.05f).Value;
    app.ActiveWorld.Scene.AddNode(new MeshNode { MaterialHandle = mirrorMat }, "MirrorQuad");

    var camNode = new FreeLookNode(app.Input!) { Fov = 60f };
    app.ActiveWorld.Scene.AddNode(camNode, "MainCamera");
    camNode.LocalTransform = camNode.LocalTransform with { Position = new Vector3(0f, 0f, 10f) };
    app.ActiveWorld.ActiveCamera = camNode.Entity;

    app.ActiveWorld.Scene.AddNode(new LightNode { 
        Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)), 
        Intensity = 1.0f 
    }, "Sun");

    Console.WriteLine("[Example] 05_skybox_ibl — WASD to move, Mouse to look, Shift/Ctrl to fly");
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = () =>
{
    app.Renderer.ClearColor(0.05f, 0.05f, 0.05f, 1f);
    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[Example] FPS: {fps:F2}");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);

sealed class FreeLookNode(Input input) : CameraNode
{
    private float _speed = 5.0f;
    private float _sensitivity = 0.1f;
    private float _pitch = 0f;
    private float _yaw = -90f;

    protected override void OnUpdate(float dt)
    {
        // ── Rotation (Mouse) ──────────────────────────────────────────────────
        // Vector2 delta = input.MouseDelta;
        // _yaw   += delta.X * _sensitivity;
        // _pitch -= delta.Y * _sensitivity;
        // _pitch = Math.Clamp(_pitch, -89f, 89f);

        // Quaternion rot = Quaternion.CreateFromYawPitchRoll(
        //     _yaw * MathF.PI / 180f, 
        //     _pitch * MathF.PI / 180f, 
        //     0f);

        // ── Movement (WASD) ───────────────────────────────────────────────────
        // Vector3 forward = Vector3.Transform(-Vector3.UnitZ, rot);
        // Vector3 right   = Vector3.Transform(Vector3.UnitX, rot);
        // Vector3 up      = Vector3.UnitY;

        // Vector3 moveDir = Vector3.Zero;
        // if (input.IsKeyDown(87)) moveDir += forward; // W
        // if (input.IsKeyDown(83)) moveDir -= forward; // S
        // if (input.IsKeyDown(65)) moveDir -= right;   // A
        // if (input.IsKeyDown(68)) moveDir += right;   // D
        // if (input.IsKeyDown(340)) moveDir += up;     // Shift
        // if (input.IsKeyDown(341)) moveDir -= up;     // Ctrl

        // if (moveDir != Vector3.Zero)
        //     moveDir = Vector3.Normalize(moveDir);

        // LocalTransform = LocalTransform with
        // {
        //     Position = LocalTransform.Position + moveDir * _speed * dt,
        //     Rotation = rot
        // };
    }
}
