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

    var mirrorMat = app.Renderer.CreateMaterial(1f, 1f, 1f, 1f, metallic: 0.5f, roughness: 0.5f).Value;
    app.ActiveWorld.Scene.AddNode(new MeshNode { MaterialHandle = mirrorMat }, "MirrorQuad");

    var camNode = new FreeLookNode(app.Input!) { Fov = 60f };
    app.ActiveWorld.Scene.AddNode(camNode, "MainCamera");
    camNode.LocalTransform = camNode.LocalTransform with { Position = new Vector3(0f, 0f, 10f) };
    app.ActiveWorld.ActiveCamera = camNode.Entity;

    app.ActiveWorld.Scene.AddNode(new LightNode { 
        Direction = Vector3.Normalize(new(0.5f, 1f, 0.5f)), 
        Intensity = 1.0f 
    }, "Sun");

    app.Renderer.SetTonemapping(true, 1.0f, 2.2f);
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

// Arrow keys: look — WASD: move — Shift/Ctrl: fly up/down
sealed class FreeLookNode(Input input) : CameraNode
{
    private float _speed       = 8.0f;
    private float _rotateDeg   = 90.0f; // degrees per second
    private float _pitch       = 0f;
    private float _yaw         = 0f;    // start facing -Z

    protected override void OnUpdate(float dt)
    {
        // ── Rotation (arrow keys) ─────────────────────────────────────────────
        bool anyKey = false;
        if (input.IsKeyDown(262)) { _yaw   -= _rotateDeg * dt; anyKey = true; } // Right arrow
        if (input.IsKeyDown(263)) { _yaw   += _rotateDeg * dt; anyKey = true; } // Left arrow
        if (input.IsKeyDown(265)) { _pitch += _rotateDeg * dt; anyKey = true; } // Up arrow
        if (input.IsKeyDown(264)) { _pitch -= _rotateDeg * dt; anyKey = true; } // Down arrow
        if (anyKey) Console.Write($"\r[Camera] yaw={_yaw:F1} pitch={_pitch:F1}          ");
        _pitch = Math.Clamp(_pitch, -89f, 89f);

        var rot = Quaternion.CreateFromYawPitchRoll(
            _yaw   * MathF.PI / 180f,
            _pitch * MathF.PI / 180f,
            0f);

        // ── Movement (WASD + Shift/Ctrl) ──────────────────────────────────────
        var forward = Vector3.Transform(-Vector3.UnitZ, rot);
        var right   = Vector3.Transform( Vector3.UnitX, rot);

        var move = Vector3.Zero;
        if (input.IsKeyDown(87))  move += forward;       // W
        if (input.IsKeyDown(83))  move -= forward;       // S
        if (input.IsKeyDown(65))  move -= right;         // A
        if (input.IsKeyDown(68))  move += right;         // D
        if (input.IsKeyDown(340)) move += Vector3.UnitY; // Shift
        if (input.IsKeyDown(341)) move -= Vector3.UnitY; // Ctrl
        if (move != Vector3.Zero) move  = Vector3.Normalize(move);

        LocalTransform = LocalTransform with
        {
            Position = LocalTransform.Position + move * _speed * dt,
            Rotation = rot,
        };
    }
}
