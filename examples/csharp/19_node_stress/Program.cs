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

// Names the borrowed child something the borrow does not ask for, so a run can show
// the coupling check failing. A check nobody has ever seen fail is a check nobody
// knows the range of.
bool breakBorrow = Environment.GetCommandLineArgs().Contains("--break-borrow");

ScriptHost? churnWorld = null;
var coupled = new List<Coupled>();

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
        if (kind is "coupled" or "both")
            for (int i = 0; i < instances; i++)
            {
                var parent = world.AddNode(new Coupled { Rate = 1f + i * 0.001f, Threshold = 1f }, $"Coupled{i}");
                var echo = world.AddNode(new Echo(), breakBorrow ? "NotEcho" : "Echo", parent);
                world.Connect<Crossed>(parent, echo);
                coupled.Add(parent);
            }
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
    return 0;
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

var failures = CheckCoupling(coupled, ticks);
foreach (var line in failures) Console.WriteLine($"[19_node_stress] FAIL {line}");
if (failures.Count == 0 && coupled.Count > 0)
    Console.WriteLine($"[19_node_stress] borrows and signals held across {coupled.Count} parents");

runtime.UnloadModules(sp);
return failures.Count;

/// <summary>
/// Checks the two paths a windowed game used to be the only witness of: a named borrow
/// that resolves, and a signal that reaches its handler. Reported as failures rather
/// than asserted so one run says how many parents are wrong, not just that one is.
/// </summary>
static List<string> CheckCoupling(List<Coupled> parents, int ticks)
{
    var failures = new List<string>();
    for (int i = 0; i < parents.Count; i++)
    {
        var parent = parents[i];
        if (parent.Children.Count != 1) { failures.Add($"'{parent.Name}' has {parent.Children.Count} children, expected 1"); continue; }
        if (parent.Children[0] is not Echo echo) { failures.Add($"'{parent.Name}' child is not an Echo"); continue; }

        if (echo.Notes == 0) failures.Add($"'{parent.Name}' borrow never reached its child");
        else if (echo.Notes < ticks) failures.Add($"'{parent.Name}' borrow reached {echo.Notes} of {ticks} ticks");
        if (echo.Signals == 0) failures.Add($"'{parent.Name}' signal never arrived");
        if (echo.Last != parent.Value) failures.Add($"'{parent.Name}' child saw {echo.Last}, parent holds {parent.Value}");
    }
    return failures;
}

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
