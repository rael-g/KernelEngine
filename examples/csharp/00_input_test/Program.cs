using KernelEngine.Ecs.Flecs;
using KernelEngine.Framework;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.Scheduler.Enki;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using KernelEngine.Logger;
using KernelEngine.Input;

// 00_input_test — smoke test for the View-funneled input. The new Framework
// exposes input via polling (`view.IsKeyDown(int)`); cross-frame edge
// detection lives in the node. The legacy InputEvent (KeyDown/KeyUp/Scroll/
// Mouse) pipeline isn't ported yet — Kanban tracks it separately.
//
// Click the window first so it has keyboard focus, then:
//   • Tap a key (A-Z, Space, arrows)  → "KEY DOWN ..." / "KEY UP ..."
//   • Escape                          → quit

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .Add<IEcs, FlecsEcs>()
    .Add<IScheduler, EnkiScheduler>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(640, 160, "KernelEngine — 00 Input Test (click window, then type)"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(clearColor: new System.Numerics.Vector4(0.05f, 0.05f, 0.08f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule(tree =>
    {
        Console.WriteLine("[KernelEngine] Example: 00_input_test");
        Console.WriteLine("[KernelEngine] Features: input_polling, key_edge_detection");
        tree.AddNode(new KeyEdgeListener(), "InputListener");
    }));

using var sp = services.BuildServiceProvider();
var window  = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[00_input_test] Loop running. Close the window to exit.");

var clock = System.Diagnostics.Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    runtime.Tick((float)(now - prev));
    prev = now;
}

runtime.UnloadModules(sp);

Console.WriteLine("[00_input_test] Exited cleanly.");

// ── Walks a fixed set of GLFW keycodes each frame, diffs against previous ────

sealed class KeyEdgeListener : Node
{
    // Subset that covers what most tests want: letters A-Z, digits 0-9, space,
    // arrows, escape, shift/ctrl/alt. Iterating the full keyboard is fine too
    // since GLFW keycodes are sparse over [32..348].
    private static readonly (int Code, string Name)[] s_keys =
    {
        (32,  "Space"),
        (256, "Escape"),
        (257, "Enter"),
        (258, "Tab"),
        (262, "Right"), (263, "Left"), (264, "Down"), (265, "Up"),
        (340, "LShift"), (341, "LCtrl"), (342, "LAlt"),
    };

    private readonly bool[] _prev = new bool[s_keys.Length];

    protected override void OnBind(NodeWorld nodeWorld) { }

    protected override void OnUpdate(in View view)
    {
        for (int i = 0; i < s_keys.Length; i++)
        {
            bool down = view.IsKeyDown(s_keys[i].Code);
            if (down && !_prev[i])      Console.WriteLine($"KEY DOWN  {s_keys[i].Name}");
            else if (!down && _prev[i]) Console.WriteLine($"KEY UP    {s_keys[i].Name}");
            _prev[i] = down;
        }

        if (view.IsKeyDown(256)) Environment.Exit(0); // Escape
    }
}
