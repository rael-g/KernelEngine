using System.Numerics;

using KernelEngine.Common;
using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Io.Pool;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

var render = new WebgpuRenderModule();

var services = new ServiceCollection()
    .AddLogging(logging => logging.AddConsole())
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .Add<IRuntime, Runtime>()
    .AddConfig(new GlfwWindowConfig { Title = "KernelEngine — 18 Webgpu Mesh (v2)", Width = 1024, Height = 640 })
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .AddConfig(new DefaultRenderServiceConfig { ShaderDir = ExamplePaths.ShaderDir })
    .Add<IRuntimeModule>(render);

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();
var ecs = sp.GetRequiredService<INativeEcs>();

runtime.LoadModules(sp);

var renderService = sp.GetRequiredService<IRenderService>();
var orange = renderService.CreateMaterial("orange", new Vector4(0.85f, 0.35f, 0.2f, 1.0f));

EcsRegistry reg;
unsafe { reg = EcsRegistry.Borrow(((INativeEcs)ecs).Native); }

var transformCid = reg.RegisterComponent<TransformComponent>("transform");
var worldCid = reg.RegisterComponent<WorldTransformComponent>("world_transform");
var cameraCid = reg.RegisterComponent<CameraComponent>(CameraComponent.Name);
var meshCid = reg.RegisterComponent<MeshComponent>(MeshComponent.Name);
var lightCid = reg.RegisterComponent<DirectionalLightComponent>("directional_light");

var cam = reg.CreateEntity();
ref var camT = ref reg.AddComponent<TransformComponent>(cam, transformCid)[0];
camT = TransformComponent.Default;
camT.Position = new Vector3(1.5f, 1.5f, -3.0f);
ref var camW = ref reg.AddComponent<WorldTransformComponent>(cam, worldCid)[0];
camW.Matrix = Matrix4x4.CreateTranslation(camT.Position);
ref var camC = ref reg.AddComponent<CameraComponent>(cam, cameraCid)[0];
camC = CameraComponent.Default with { FarPlane = 100.0f };

var ent = reg.CreateEntity();
ref var entT = ref reg.AddComponent<TransformComponent>(ent, transformCid)[0];
entT = TransformComponent.Default;
ref var entW = ref reg.AddComponent<WorldTransformComponent>(ent, worldCid)[0];
entW.Matrix = Matrix4x4.Identity;
ref var entM = ref reg.AddComponent<MeshComponent>(ent, meshCid)[0];
entM = MeshComponent.Default with { Material = orange };
entM.PrimitiveText = "cube";

var sun = reg.CreateEntity();
ref var sunL = ref reg.AddComponent<DirectionalLightComponent>(sun, lightCid)[0];
sunL = DirectionalLightComponent.Default with
{
    Direction = new Vector3(-0.4f, -1.0f, -0.3f),
    Color = Vector3.One,
    Intensity = 3.0f,
    Ambient = new Vector3(0.03f, 0.03f, 0.04f),
};

Console.WriteLine("[18_webgpu_mesh] Drawing a lit cube. Close the window to exit.");

var sw = System.Diagnostics.Stopwatch.StartNew();
double prev = sw.Elapsed.TotalSeconds;
while (!window.ShouldClose())
{
    double now = sw.Elapsed.TotalSeconds;
    window.PollEvents();
    runtime.Tick((float)(now - prev));
    prev = now;
}
runtime.UnloadModules();

Console.WriteLine("[18_webgpu_mesh] Exited cleanly.");
