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

// 10_hdr_tonemapping — a very bright point light sits close to three spheres
// and a floor plane. 1/r² falloff makes the near sphere's specular peak far
// exceed 1.0; the ACES Narkowicz curve rolls it to a warm glow rather than
// clipping flat. The floor shows the falloff gradient: bright under the lamp,
// nearly black at the edges.

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 10 HDR Tonemapping"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new Vector4(0.0f, 0.0f, 0.0f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 10_hdr_tonemapping");
        Console.WriteLine("[KernelEngine] Features: hdr_intermediate, aces_tonemapping");

        // Camera looking slightly down at the scene from behind and above.
        var cam = tree.AddNode(new Camera { Fov = 55f, Near = 0.1f, Far = 200f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 4f, 12f) };

        var sphere = KernelEngine.Render.MeshPrimitives.UvSphere(resources, radius: 1f, rings: 32, segments: 48);
        var floor  = KernelEngine.Render.MeshPrimitives.Plane(resources);

        // Very smooth materials — tight specular lobe pushes the peak far past 1.0,
        // making the ACES gradient obvious. Rough materials spread the energy too
        // wide and the highlight stays below the tonemapping threshold.
        var matGray   = resources.CreateMaterial("gray", new Vector4(0.8f, 0.8f, 0.8f, 1f), metallic: 0.0f, roughness: 0.05f);
        var matCopper = resources.CreateMaterial("copper", new Vector4(0.9f, 0.5f, 0.2f, 1f), metallic: 0.9f, roughness: 0.08f);
        var matBlue   = resources.CreateMaterial("blue", new Vector4(0.2f, 0.4f, 0.9f, 1f), metallic: 0.0f, roughness: 0.12f);
        var matFloor  = resources.CreateMaterial("floor", new Vector4(0.3f, 0.3f, 0.3f, 1f), metallic: 0.0f, roughness: 0.9f);

        // Floor — large enough to show the falloff halo.
        var floorNode = tree.AddNode(new MeshRenderer { MeshHandle = floor, MaterialHandle = matFloor }, "Floor");
        floorNode.LocalTransform = floorNode.LocalTransform with
        {
            Position = new Vector3(0f, -1f, 0f),
            Scale    = new Vector3(20f, 1f, 20f),
        };

        // Three spheres; near sphere is 1.5 units from the light, far is ~7.
        var s0 = tree.AddNode(new MeshRenderer { MeshHandle = sphere, MaterialHandle = matGray   }, "SphereNear");
        var s1 = tree.AddNode(new MeshRenderer { MeshHandle = sphere, MaterialHandle = matCopper }, "SphereMid");
        var s2 = tree.AddNode(new MeshRenderer { MeshHandle = sphere, MaterialHandle = matBlue   }, "SphereFar");
        s0.LocalTransform = s0.LocalTransform with { Position = new Vector3(-3f, 0f, 0f) };
        s1.LocalTransform = s1.LocalTransform with { Position = new Vector3( 0f, 0f, 0f) };
        s2.LocalTransform = s2.LocalTransform with { Position = new Vector3( 3f, 0f, 0f) };

        // Negligible ambient — the demo relies on the point light falloff being
        // visible, so the background must stay near-black.
        tree.AddNode(new AmbientLight { Color = new Vector3(0.01f, 0.01f, 0.015f) }, "Ambient");

        // Lamp 2.5 units from the near sphere. Intensity 5 keeps the diffuse
        // in the 0.3–0.7 range so the sphere body shows its colour; the GGX
        // specular peak for roughness 0.05 is ~127× the irradiance, pushing
        // the highlight well past 1.0. ACES maps that to a warm glow with a
        // visible gradient — the body colour and the hot spot are both legible.
        var light = tree.AddNode(new PointLight
        {
            Color     = new Vector3(1f, 0.92f, 0.80f),
            Intensity = 5f,
            Radius    = 20f,
        }, "Lamp");
        light.LocalTransform = light.LocalTransform with { Position = new Vector3(-3f, 2f, 1.5f) };
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[10_hdr_tonemapping] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[10_hdr_tonemapping] Exited cleanly.");
