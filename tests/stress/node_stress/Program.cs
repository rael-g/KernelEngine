using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Runtime;
using KernelEngine.TaskPool.Enki;

using NodeStress;

int instances = ArgValue("--instances", 2000);
int ticks = ArgValue("--ticks", 300);
uint workers = (uint)ArgValue("--workers", 0);

using var pool = new EnkiTaskPool(workers);
using var ecs = new FlecsEcsRegistry(1048576);
using var runtime = new DefaultRuntime(ecs, pool, 1.0f / 60.0f, 0.25f, 256);
using var tree = new DefaultSceneTree(ecs, runtime);
using var types = new DefaultNodeTypes(runtime, ecs, tree);

var world = new NodeWorld(types);
world.RegisterEvent<Crossed>();
var mover = world.Register(new Mover());
var raiser = world.Register(new Raiser());
var listener = world.Register(new Listener());

var commands = runtime.Commands();
for (var i = 0; i < instances; i++) types.Spawn(commands, mover, $"Mover{i}", default);
for (var i = 0; i < instances / 10; i++) types.Spawn(commands, raiser, $"Raiser{i}", default);
types.Spawn(commands, listener, "Listener", default);

Console.WriteLine($"[19_node_stress] {instances} movers, {instances / 10} raisers, {ticks} ticks, {pool.GetNumWorkers()} workers");

const float dt = 1f / 60f;
for (var i = 0; i < 30; i++) runtime.Tick(dt);
Listener.Heard = 0;

var clock = System.Diagnostics.Stopwatch.StartNew();
for (var i = 0; i < ticks; i++) runtime.Tick(dt);
clock.Stop();

Console.WriteLine($"[19_node_stress] {clock.Elapsed.TotalMilliseconds / ticks:F3} ms/tick");
var expected = (long)(instances / 10) * (ticks / 2);
var failed = Listener.Heard < expected / 2;
Console.WriteLine(failed
    ? $"[19_node_stress] FAIL the listener heard {Listener.Heard} events, expected about {expected}"
    : $"[19_node_stress] the listener heard {Listener.Heard} events");

runtime.Flush();
runtime.UnloadModules();
return failed ? 1 : 0;

static int ArgValue(string name, int fallback)
{
    var argv = Environment.GetCommandLineArgs();
    for (var i = 0; i < argv.Length - 1; i++)
        if (argv[i] == name && int.TryParse(argv[i + 1], out var v)) return v;
    return fallback;
}
