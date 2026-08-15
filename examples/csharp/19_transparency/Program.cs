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

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 19 Transparency"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new Vector4(0.05f, 0.05f, 0.08f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 19_transparency");
        Console.WriteLine("[KernelEngine] Features: transparent_forward, back_to_front_sort, blend, refraction");

        const uint faceSize = 64;
        var faces = new byte[faceSize * faceSize * 4 * 6];
        (byte R, byte G, byte B)[] skyColors =
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
                faces[off + i * 4 + 0] = skyColors[f].R;
                faces[off + i * 4 + 1] = skyColors[f].G;
                faces[off + i * 4 + 2] = skyColors[f].B;
                faces[off + i * 4 + 3] = 255;
            }
        }
        var cubemap = resources.UploadCubemap("sky_cubemap", faceSize, faces);
        tree.AddNode(new Skybox { CubemapHandle = cubemap }, "Skybox");

        tree.AddNode(new DirectionalLight
        {
            Direction = Vector3.Normalize(new Vector3(0.4f, 1f, 0.6f)),
            Color     = Vector3.One,
            Intensity = 2f,
        }, "Sun");

        var cam = tree.AddNode(new Camera { Fov = 60f, NearPlane = 0.1f, FarPlane = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 0f, 6f) };

        var cube  = KernelEngine.Render.MeshPrimitives.Cube(resources);
        var gray  = resources.CreateMaterial("gray", new Vector4(0.6f, 0.6f, 0.6f, 1f));
        var back  = tree.AddNode(new MeshRenderer { MeshHandle = cube, MaterialHandle = gray }, "OpaqueCube");
        back.LocalTransform = back.LocalTransform with { Position = new Vector3(0f, 0f, -2f), Scale = new Vector3(1.5f) };

        var quad = KernelEngine.Render.MeshPrimitives.Quad(resources);
        var red  = resources.CreateMaterial("red", new Vector4(1f, 0.15f, 0.15f, 0.5f), alphaMode: AlphaMode.Blend);
        var blue = resources.CreateMaterial("blue", new Vector4(0.15f, 0.35f, 1f, 0.5f), alphaMode: AlphaMode.Blend);

        var far  = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = red }, "FarQuad");
        far.LocalTransform = far.LocalTransform with { Position = new Vector3(-0.4f, 0f, 0f), Scale = new Vector3(2f) };

        var near = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = blue }, "NearQuad");
        near.LocalTransform = near.LocalTransform with { Position = new Vector3(0.4f, 0f, 1f), Scale = new Vector3(2f) };

        var glass = resources.CreateMaterial("glass", new Vector4(1f, 1f, 1f, 0.15f), alphaMode: AlphaMode.Blend,
            ior: 1.5f, distortionStrength: 0.25f);
        var glassNode = tree.AddNode(new MeshRenderer { MeshHandle = quad, MaterialHandle = glass }, "GlassQuad");
        glassNode.LocalTransform = glassNode.LocalTransform with { Position = new Vector3(2.5f, 0f, 2f), Scale = new Vector3(2f) };
    }));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[19_transparency] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[19_transparency] Exited cleanly.");
