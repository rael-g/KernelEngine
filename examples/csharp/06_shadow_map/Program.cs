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

// 06_shadow_map — directional shadow casting onto a floor plane. A red cube sits
// above a gray floor; the sun's azimuth sweeps over time so the cube's shadow
// slides across the floor, making the shadow projection visible at a glance.
// Render v2 (webgpu): a discrete shadow-depth pass renders the casters from the
// light's point of view into a depth map, and the forward pass samples it.

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1280, 720, "KernelEngine — 06 Shadow Map"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new Vector4(0.1f, 0.1f, 0.15f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((tree, sp) =>
    {
        var resources = sp.GetRequiredService<IRenderResources>();
        Console.WriteLine("[KernelEngine] Example: 06_shadow_map");
        Console.WriteLine("[KernelEngine] Features: shadow_map_directional, ortho_light_frustum, animated_sun");

        var planeMesh = KernelEngine.Render.MeshPrimitives.Plane(resources);
        var cubeMesh  = KernelEngine.Render.MeshPrimitives.Cube(resources);

        var floorMat = resources.CreateMaterial("floor", new Vector4(0.5f, 0.5f, 0.5f, 1f), roughness: 0.8f);
        var redMat   = resources.CreateMaterial("red", new Vector4(0.8f, 0.2f, 0.2f, 1f), metallic: 0.2f, roughness: 0.3f);

        tree.AddNode(new AnimatedSun
        {
            Color     = Vector3.One,
            Intensity = 3f,
            Ambient   = new(0.15f, 0.15f, 0.15f),
        }, "Sun");

        // Look-at-origin camera (identity rotation): from above and behind, it
        // frames the floor + cube + the cast shadow without a free-look rig.
        var cam = tree.AddNode(new Camera { Fov = 60f, Near = 0.1f, Far = 1000f }, "Camera");
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0f, 5f, 10f) };

        var floor = tree.AddNode(new MeshRenderer { MeshHandle = planeMesh, MaterialHandle = floorMat }, "Floor");
        floor.LocalTransform = floor.LocalTransform with { Scale = new Vector3(20f, 1f, 20f) };

        var caster = tree.AddNode(new MeshRenderer { MeshHandle = cubeMesh, MaterialHandle = redMat }, "Caster");
        caster.LocalTransform = caster.LocalTransform with { Position = new Vector3(0f, 1f, 0f) };
    }));

using var sp = services.BuildServiceProvider();
var window   = sp.GetRequiredService<IWindow>();
var runtime  = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[06_shadow_map] Loop running. Close the window to exit.");

var clock = Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[06_shadow_map] Exited cleanly.");

// ── Animated sun — direction sweeps in azimuth ───────────────────────────────
// The light travels downward (negative Y) so it lights the floor; the X term
// sweeps with sin(t) so the cube's shadow slides across the floor.

sealed class AnimatedSun : DirectionalLight
{
    private float _t;

    protected override void OnUpdate(in View view)
    {
        _t += view.DeltaTime;
        float a = MathF.Sin(_t * 0.8f);
        Direction = Vector3.Normalize(new Vector3(a * 0.8f, -1.0f, 0.5f));
    }
}
