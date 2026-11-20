using KernelEngine;
using KernelEngine.Framework.Nodes;
using KernelEngine.Schedule.Native;
using KernelEngine.Scheduler.Native;

using Microsoft.Extensions.DependencyInjection;

using NodeStress;

int instances = ArgValue("--instances", 2000);
int ticks = ArgValue("--ticks", 300);
uint workers = (uint)ArgValue("--workers", 0);

using var services = new ServiceCollection().AddDefaultKernelEngine(AppContext.BaseDirectory, "headless.composition").BuildServiceProvider();
services.GetRequiredService<DefaultProject>().Configuration.SetInt("job", "worker_count", workers);
var host = services.GetRequiredService<KernelEngineHost>();
host.Start();
var types = services.GetRequiredKeyedService<INodeTypes>("node_types");
var scheduler = Instances.Scheduler(host);

var world = services.GetRequiredService<NodeWorld>();
world.RegisterEvent<Crossed>();
var mover = world.Register(new Mover());
var raiser = world.Register(new Raiser());
var listener = world.Register(new Listener());

var commands = Instances.PreUpdate(host).Commands();
for (var i = 0; i < instances; i++) types.Spawn(commands, mover, $"Mover{i}", default);
for (var i = 0; i < instances / 10; i++) types.Spawn(commands, raiser, $"Raiser{i}", default);
types.Spawn(commands, listener, "Listener", default);

Console.WriteLine($"[19_node_stress] {instances} movers, {instances / 10} raisers, {ticks} ticks, {workers} workers asked");

const float dt = 1f / 60f;
for (var i = 0; i < 30; i++) scheduler.Tick(dt);
Listener.Heard = 0;

var clock = System.Diagnostics.Stopwatch.StartNew();
for (var i = 0; i < ticks; i++) scheduler.Tick(dt);
clock.Stop();

Console.WriteLine($"[19_node_stress] {clock.Elapsed.TotalMilliseconds / ticks:F3} ms/tick");
var expected = (long)(instances / 10) * (ticks / 2);
var failed = Listener.Heard < expected / 2;
Console.WriteLine(failed
    ? $"[19_node_stress] FAIL the listener heard {Listener.Heard} events, expected about {expected}"
    : $"[19_node_stress] the listener heard {Listener.Heard} events");

scheduler.Shutdown();
return failed ? 1 : 0;

static int ArgValue(string name, int fallback)
{
    var argv = Environment.GetCommandLineArgs();
    for (var i = 0; i < argv.Length - 1; i++)
        if (argv[i] == name && int.TryParse(argv[i + 1], out var v)) return v;
    return fallback;
}

static unsafe class Instances
{
    public static KernelEngine.Scheduler.Scheduler Scheduler(KernelEngineHost host) =>
        KernelEngine.Scheduler.Scheduler.Borrow((ke_scheduler*)host.Instance("scheduler", "ke_scheduler"));

    public static KernelEngine.Schedule.Schedule PreUpdate(KernelEngineHost host) =>
        KernelEngine.Schedule.Schedule.Borrow((ke_schedule*)host.Instance("pre_update", "ke_schedule"));
}
