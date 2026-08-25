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
int churn = ArgValue("--churn", 0);
string kind = ArgText("--type", "both");

ScriptHost? churnWorld = null;

var services = new ServiceCollection()
    .Add<INativeEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule(world =>
    {
        churnWorld = world;
        if (churn > 0) return;
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

if (churn > 0)
{
    var world = churnWorld!;
    RunChurn(world, instances);

    var settled = GC.GetTotalMemory(forceFullCollection: true);
    for (int round = 0; round < churn; round++) RunChurn(world, instances);
    var after = GC.GetTotalMemory(forceFullCollection: true);

    var perNode = (double)(after - settled) / (churn * instances);
    Console.WriteLine($"[19_node_stress] churn: {churn} rounds x {instances} nodes bound then destroyed");
    Console.WriteLine($"[19_node_stress] managed heap {settled / 1024} KiB -> {after / 1024} KiB "
        + $"({perNode:F1} bytes retained per node created)");
    Console.WriteLine("[19_node_stress] a node whose handle is never freed cannot be collected, "
        + "so a real leak grows with rounds instead of settling");
    runtime.UnloadModules(sp);
    return;
}

static void RunChurn(ScriptHost world, int count)
{
    var made = new List<Mover>(count);
    for (int i = 0; i < count; i++) made.Add(world.AddNode(new Mover { Rate = 1f }, $"Churn{i}"));
    for (int i = 0; i < made.Count; i++) made[i].Destroy();
}

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
