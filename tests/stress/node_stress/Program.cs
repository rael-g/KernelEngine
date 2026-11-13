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

using var jobs = new EnkiJobSystem(new KernelEngine.Job.JobSystemConfig { WorkerCount = workers });
using var ecs = new FlecsEcsRegistry(new KernelEngine.Ecs.EcsConfig { ReservedIdCapacity = 1048576 });
using var first = new DefaultSchedule(ecs, jobs, new ScheduleConfig { RefuseAmbiguity = false });
using var fixedSchedule = new DefaultSchedule(ecs, jobs, new ScheduleConfig { RefuseAmbiguity = false });
using var main = new DefaultSchedule(ecs, jobs, new ScheduleConfig { RefuseAmbiguity = false });
using var scheduler = new DefaultScheduler(new SchedulerConfig { FixedDt = 1.0f / 60.0f, FixedDtMaxAccum = 0.25f });
scheduler.AddSchedule(first, SchedulerCadence.EveryTick);
scheduler.AddSchedule(fixedSchedule, SchedulerCadence.Fixed);
scheduler.AddSchedule(main, SchedulerCadence.EveryTick);
var preUpdate = first.RegisterSet("pre_update", []);
var fixedUpdate = fixedSchedule.RegisterSet("fixed_update", []);
var update = main.RegisterSet("update", []);
var propagation = main.RegisterSet("post_update", [update]);
using var tree = new DefaultSceneTree(ecs, main, new() { Set = propagation });
using var types = new DefaultNodeTypes(scheduler, first, fixedSchedule, main, ecs, tree, null, new NodeTypesConfig { PreUpdate = preUpdate, Update = update, FixedUpdate = fixedUpdate, PostUpdate = propagation });

var world = new NodeWorld(types);
world.RegisterEvent<Crossed>();
var mover = world.Register(new Mover());
var raiser = world.Register(new Raiser());
var listener = world.Register(new Listener());

var commands = first.Commands();
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
