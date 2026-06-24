using System.Numerics;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;
using KernelEngine.Logger;
using Microsoft.Extensions.DependencyInjection;

// Render v2 (webgpu) first 3D scene: a lit cube drawn by the render core's
// forward pass. The host uploads the mesh and populates Camera + Mesh + Transform
// components; the forward pass (a KE_PHASE_RENDER system installed by the module)
// reads them and draws. No render calls in the loop — only runtime.Tick.

var render = new WebgpuRenderModule();

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(1024, 640, "KernelEngine — 18 Webgpu Mesh (v2)"))
    .Add<IRuntimeModule>(render);

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();
var ecs     = sp.GetRequiredService<IEcs>();

runtime.LoadModules(sp);

// ── Upload the cube + material, populate the scene (camera + one mesh entity) ─
var cube   = MeshPrimitives.Cube(render);
var orange = render.CreateMaterial(new Vector4(0.85f, 0.35f, 0.2f, 1.0f));

EcsRegistry reg;
unsafe { reg = new EcsRegistry(((INativeEcs)ecs).Native); }

var transformCid = reg.RegisterComponent<TransformComponent>("transform");
var cameraCid    = reg.RegisterComponent<CameraComponent>(CameraComponent.Name);
var meshCid      = reg.RegisterComponent<MeshComponent>(MeshComponent.Name);

var cam = reg.CreateEntity();
ref var camT = ref reg.AddComponent<TransformComponent>(cam, transformCid)[0];
camT = TransformComponent.Identity;
camT.Position = new Vector3(1.5f, 1.5f, -3.0f);
ref var camC = ref reg.AddComponent<CameraComponent>(cam, cameraCid)[0];
camC = new CameraComponent { Fov = 60.0f, NearPlane = 0.1f, FarPlane = 100.0f };

var ent = reg.CreateEntity();
ref var entT = ref reg.AddComponent<TransformComponent>(ent, transformCid)[0];
entT = TransformComponent.Identity;
entT.WorldMatrix = Matrix4x4.Identity;
ref var entM = ref reg.AddComponent<MeshComponent>(ent, meshCid)[0];
entM = new MeshComponent { Mesh = cube, Material = orange };

Console.WriteLine("[18_webgpu_mesh] Drawing a lit cube. Close the window to exit.");

var sw = System.Diagnostics.Stopwatch.StartNew();
double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

Console.WriteLine("[18_webgpu_mesh] Exited cleanly.");
