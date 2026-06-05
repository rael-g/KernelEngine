using System.Diagnostics;
using KernelEngine.Kernel;
using LuaSpike;

// ── Thread name (World.Update asserts ke.sim) ─────────────────────────────────
KernelThread.SetCurrentName("ke.sim");

const int WarmupFrames    = 10;
const int BenchmarkFrames = 1000;
var scriptPath = Path.Combine(AppContext.BaseDirectory, "scripts", "paddle.lua");

Console.WriteLine("=== Tier S — Lua spike ===");
Console.WriteLine($"Script : {scriptPath}");
Console.WriteLine($"Frames : {BenchmarkFrames} (+ {WarmupFrames} warmup)");
Console.WriteLine();

// ── Phase 1: C# ScriptBridge baseline ────────────────────────────────────────

Console.WriteLine("--- Phase 1: C# ScriptBridge baseline ---");
using (var allocator = new MallocAllocator())
using (var world = new World(allocator))
{
    var entity = world.Registry.CreateEntity();
    int startCount  = 0;
    int updateCount = 0;

    world.RegisterScript(entity,
        onStart:  () => startCount++,
        onUpdate: _ => updateCount++);

    // Warmup
    for (int i = 0; i < WarmupFrames; i++) world.Update();

    // Reset counters after warmup
    startCount  = 0;
    updateCount = 0;

    var sw = Stopwatch.StartNew();
    for (int i = 0; i < BenchmarkFrames; i++) world.Update();
    sw.Stop();

    Console.WriteLine($"  on_start  calls : {startCount}  (expected 0 — already fired in warmup)");
    Console.WriteLine($"  on_update calls : {updateCount}  (expected {BenchmarkFrames})");
    Console.WriteLine($"  Total time      : {sw.ElapsedMilliseconds} ms");
    Console.WriteLine($"  Per frame       : {sw.Elapsed.TotalMicroseconds / BenchmarkFrames:F1} µs");

    world.UnregisterScript(entity);
}

Console.WriteLine();

// ── Phase 2: Lua binding via ke_script_component ──────────────────────────────

Console.WriteLine("--- Phase 2: Lua script via ke_script_component ---");
Console.WriteLine("(first 3 frames verbose, then silent benchmark)");
Console.WriteLine();

using (var allocator = new MallocAllocator())
using (var world = new World(allocator))
{
    var entity = world.Registry.CreateEntity();

    LuaScriptBridge.Register(world.Registry, world.ScriptComponentId, entity, scriptPath);

    // 3 verbose frames (Lua prints to stdout)
    for (int i = 0; i < 3; i++) world.Update();

    Console.WriteLine();
    Console.WriteLine("--- silent benchmark ---");

    // Swap to a silent Lua state for fair timing
    LuaScriptBridge.Unregister(entity);
    entity = world.Registry.CreateEntity();

    var silentScript = Path.Combine(AppContext.BaseDirectory, "scripts", "paddle_silent.lua");
    if (!File.Exists(silentScript))
    {
        // Generate a no-print version inline
        File.WriteAllText(silentScript,
            "local t = 0.0\n" +
            "function on_awake(e) end\n" +
            "function on_start(e) end\n" +
            "function on_update(e, dt) t = t + dt end\n" +
            "function on_late_update(e, dt) end\n" +
            "function on_destroy(e) end\n");
    }

    LuaScriptBridge.Register(world.Registry, world.ScriptComponentId, entity, silentScript);

    // Warmup
    for (int i = 0; i < WarmupFrames; i++) world.Update();

    var sw = Stopwatch.StartNew();
    for (int i = 0; i < BenchmarkFrames; i++) world.Update();
    sw.Stop();

    Console.WriteLine($"  Total time : {sw.ElapsedMilliseconds} ms");
    Console.WriteLine($"  Per frame  : {sw.Elapsed.TotalMicroseconds / BenchmarkFrames:F1} µs");

    LuaScriptBridge.Unregister(entity);
}

Console.WriteLine();
Console.WriteLine("=== spike complete ===");
Console.WriteLine("Verify: on_awake → on_start → on_update → on_late_update order above.");
Console.WriteLine("Compare per-frame µs between Phase 1 and Phase 2 to assess Lua overhead.");
