using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Scheduler;
using KernelEngine.TaskPool.Enki;

using NodeStress;

int instances = ArgValue("--instances", 2000);
int ticks = ArgValue("--ticks", 300);
uint workers = (uint)ArgValue("--workers", 0);

using var pool = new EnkiTaskPool(new KernelEngine.TaskPool.TaskPoolConfig { WorkerCount = workers });
using var ecs = new FlecsEcsRegistry(new KernelEngine.Ecs.EcsConfig { ReservedIdCapacity = 1048576 });
using var scheduler = new DefaultScheduler(ecs, pool, new SchedulerConfig { FixedDt = 1.0f / 60.0f, FixedDtMaxAccum = 0.25f });
uint Phase(string name, PhaseCadence cadence) => scheduler.RegisterSet(name, scheduler.RegisterPhase(name, cadence, false), []);
var preUpdate = Phase("pre_update", PhaseCadence.EveryTick);
var fixedUpdate = Phase("fixed_update", PhaseCadence.Fixed);
var update = Phase("update", PhaseCadence.EveryTick);
var propagation = Phase("post_update", PhaseCadence.EveryTick);
using var tree = new DefaultSceneTree(ecs, scheduler, new() { Set = propagation });
using var types = new DefaultNodeTypes(scheduler, ecs, tree, null, new NodeTypesConfig { PreUpdate = preUpdate, Update = update, FixedUpdate = fixedUpdate, PostUpdate = propagation });

var world = new NodeWorld(types);
world.RegisterEvent<Crossed>();
var mover = world.Register(new Mover());
var raiser = world.Register(new Raiser());
var listener = world.Register(new Listener());

var commands = scheduler.Commands();
for (var i = 0; i < instances; i++) types.Spawn(commands, mover, $"Mover{i}", default);
for (var i = 0; i < instances / 10; i++) types.Spawn(commands, raiser, $"Raiser{i}", default);
types.Spawn(commands, listener, "Listener", default);

Console.WriteLine($"[19_node_stress] {instances} movers, {instances / 10} raisers, {ticks} ticks, {pool.GetNumWorkers()} workers");

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
