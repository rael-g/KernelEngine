using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Input;
using KernelEngine.Io.Pool;
using KernelEngine.Logger;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;

using KernelEngine.Framework.Native;

using InputAction = KernelEngine.Framework.InputAction;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddSingleton(_ => KeyEdgeListener.Actions())
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .Add<IRuntime, Runtime>()
    .AddConfig(new GlfwWindowConfig { Title = "KernelEngine — 00 Input Test (click window, then type)", Width = 640, Height = 160 })
    .Add<IRuntimeModule>(new GlfwWindowModule())
    .AddConfig(new DefaultRenderServiceConfig { ShaderDir = ExamplePaths.ShaderDir, ClearColor = new System.Numerics.Vector4(0.05f, 0.05f, 0.08f, 1.0f) })
    .Add<IRuntimeModule>(new WebgpuRenderModule())
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule(tree =>
    {
        Console.WriteLine("[KernelEngine] Example: 00_input_test");
        Console.WriteLine("[KernelEngine] Features: input_polling, key_edge_detection");
        tree.AddNode(new KeyEdgeListener(), "InputListener");
    }));

using var sp = services.BuildServiceProvider();
var window = sp.GetRequiredService<IWindow>();
var runtime = sp.GetRequiredService<IRuntime>();

runtime.LoadModules(sp);

Console.WriteLine("[00_input_test] Loop running. Close the window to exit.");

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


Console.WriteLine("[00_input_test] Exited cleanly.");

sealed class KeyEdgeListener : Node
{
    private static readonly Key[] s_keys =
    {
        Key.Space, Key.Escape, Key.Enter, Key.Tab,
        Key.Right, Key.Left, Key.Down, Key.Up,
        Key.ShiftLeft, Key.ControlLeft, Key.AltLeft,
    };

    public static InputActions Actions()
    {
        var actions = new InputActions();
        var keys = actions.AddMap("Keys", 0);
        foreach (var key in s_keys)
            actions.BindKey(actions.AddAction(keys, key.ToString(), NativeActionType.Button), key);
        return actions;
    }

    private readonly InputAction[] _keys;

    public KeyEdgeListener() => _keys = Array.ConvertAll(s_keys, k => new InputAction(this, k.ToString()));

    protected override bool HasBehavior => true;

    protected override void OnUpdate(in View view)
    {
        foreach (var key in _keys)
        {
            if (key.JustPressed) Console.WriteLine($"KEY DOWN  {key.Name}");
            else if (key.JustReleased) Console.WriteLine($"KEY UP    {key.Name}");
        }

        if (_keys[1].Down) Environment.Exit(0);
    }
}
