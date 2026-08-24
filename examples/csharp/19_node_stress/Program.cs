using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;
using KernelEngine.Scheduler.Enki;
using Microsoft.Extensions.DependencyInjection;
using NodeStress;

int instances = ArgValue("--instances", 2000);
int ticks = ArgValue("--ticks", 300);
string kind = ArgText("--type", "both");

var services = new ServiceCollection()
    .Add<INativeEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule(world =>
    {
        if (kind is "mover" or "both")
            for (int i = 0; i < instances; i++)
                world.AddNode(new Mover { Rate = 1f + i * 0.001f }, $"Mover{i}");
        if (kind is "anchored" or "both")
            for (int i = 0; i < instances; i++)
                world.AddNode(new Anchored { Rate = 1f + i * 0.001f }, $"Anchored{i}");
    }));

using var sp = services.BuildServiceProvider();
var runtime = sp.GetRequiredService<IRuntime>();
var scheduler = sp.GetRequiredService<IScheduler>();

runtime.LoadModules(sp);

var spawned = instances * (kind == "both" ? 2 : 1);
Console.WriteLine($"[19_node_stress] type={kind}, {spawned} instances, {ticks} ticks, {scheduler.NumWorkers} workers");
Console.WriteLine("[19_node_stress] Mover reaches only itself; Anchored borrows, so only Mover may be sliced");

const float dt = 1f / 60f;

for (int i = 0; i < 30; i++) runtime.Tick(dt);

var clock = System.Diagnostics.Stopwatch.StartNew();
for (int i = 0; i < ticks; i++) runtime.Tick(dt);
clock.Stop();

var perTick = clock.Elapsed.TotalMilliseconds / ticks;
Console.WriteLine($"[19_node_stress] {perTick:F3} ms/tick over {spawned} instances");

runtime.UnloadModules(sp);

static string ArgText(string name, string fallback)
{
    var argv = Environment.GetCommandLineArgs();
    for (int i = 0; i < argv.Length - 1; i++)
        if (argv[i] == name) return argv[i + 1];
    return fallback;
}

static int ArgValue(string name, int fallback)
{
    var argv = Environment.GetCommandLineArgs();
    for (int i = 0; i < argv.Length - 1; i++)
        if (argv[i] == name && int.TryParse(argv[i + 1], out var v))
            return v;
    return fallback;
}
