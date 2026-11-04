using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Input;
using KernelEngine.Io.Pool;
using KernelEngine.Logger;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .AddInputActions<DemoAction>()
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(640, 160, "KernelEngine — 20 Input Actions (WASD, Space, Tab, Esc)"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new System.Numerics.Vector4(0.05f, 0.05f, 0.08f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((_, sp) =>
    {
        Console.WriteLine("[KernelEngine] Example: 20_input_actions");
        Console.WriteLine("[KernelEngine] Features: action_events, action_phases, event_consumption");
        var actions = sp.GetRequiredService<IInputActionMap<DemoAction>>();
        var gameplay = new Gameplay();
        var menu = new Menu();
        actions.Subscribe(gameplay.OnAction);
        actions.Subscribe(menu.OnAction);
    }));

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

var clock = System.Diagnostics.Stopwatch.StartNew();
double prev = clock.Elapsed.TotalSeconds;

while (!window.ShouldClose())
{
    double now = clock.Elapsed.TotalSeconds;
    window.PollEvents();
    runtime.Tick((float)(now - prev));
    prev = now;
}
runtime.UnloadModules();


enum DemoAction
{
    Move,
    Jump,
    Menu,
    Quit,
}

sealed class Gameplay
{
    public void OnAction(ref ActionEvent evt)
    {
        if (evt.Is(DemoAction.Quit)) Environment.Exit(0);
        if (evt.Is(DemoAction.Move))
            Console.WriteLine($"[gameplay] move {evt.Phase} {evt.Vector2Value}");
        else if (evt.Is(DemoAction.Jump) && evt.Phase == ActionPhase.Started)
            Console.WriteLine("[gameplay] jump");
    }
}

sealed class Menu
{
    private bool _open;

    public void OnAction(ref ActionEvent evt)
    {
        if (evt.Is(DemoAction.Menu) && evt.Phase == ActionPhase.Started)
        {
            _open = !_open;
            Console.WriteLine(_open ? "[menu] opened: gameplay hears nothing but Quit" : "[menu] closed");
            evt.Consume();
            return;
        }
        if (!_open || evt.Is(DemoAction.Quit)) return;
        if (evt.As(out DemoAction action) && evt.Phase == ActionPhase.Started)
            Console.WriteLine($"[menu] {action}");
        evt.Consume();
    }
}
