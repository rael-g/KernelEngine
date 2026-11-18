using KernelEngine;
using KernelEngine.Async.Enki;
using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Job.Enki;
using KernelEngine.Schedule;
using KernelEngine.Scheduler;

using NodeStress;

int instances = ArgValue("--instances", 2000);
int ticks = ArgValue("--ticks", 300);
uint workers = (uint)ArgValue("--workers", 0);

using var config = new KernelEngine.Configuration.DefaultConfiguration();
config.SetInt("job", "worker_count", workers);
using var jobs = new EnkiJobSystem(config.Section("job"));
using var asyncs = new EnkiAsync(config.Section("async"));
using var ecs = new FlecsEcsRegistry(config.Section("ecs"));
DefaultSchedule Make() => new(ecs, jobs, config.Section("schedule"));
using var startup = Make();
using var preUpdate = Make();
using var fixedSchedule = Make();
using var update = Make();
using var shutdown = Make();
var schedules = new EngineSchedules { Startup = startup, PreUpdate = preUpdate, Fixed = fixedSchedule, Update = update, Shutdown = shutdown };
var sets = EngineSets.Register(schedules);
using var scheduler = new DefaultScheduler(jobs, asyncs, config.Section("scheduler"));
schedules.AddTo(scheduler);
using var tree = new DefaultSceneTree(ecs);
using var hierarchy = new SceneHierarchyModule(ecs);
schedules.Attach(hierarchy, sets);
using var types = new DefaultNodeTypes(scheduler, ecs, tree, null);
using var nodeSystems = new NodeTypesSystemsModule(types);
schedules.Attach(nodeSystems, sets);

var world = new NodeWorld(types);
world.RegisterEvent<Crossed>();
var mover = world.Register(new Mover());
var raiser = world.Register(new Raiser());
var listener = world.Register(new Listener());

var commands = schedules.PreUpdate.Commands();
for (var i = 0; i < instances; i++) types.Spawn(commands, mover, $"Mover{i}", default);
for (var i = 0; i < instances / 10; i++) types.Spawn(commands, raiser, $"Raiser{i}", default);
types.Spawn(commands, listener, "Listener", default);

Console.WriteLine($"[19_node_stress] {instances} movers, {instances / 10} raisers, {ticks} ticks, {jobs.WorkerSlots() - 1} workers");

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
