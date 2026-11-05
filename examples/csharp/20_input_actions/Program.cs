using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Native;
using KernelEngine.Input;
using KernelEngine.Io.Pool;
using KernelEngine.Logger;
using KernelEngine.Render.Webgpu;
using KernelEngine.Runtime;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Window;
using KernelEngine.Window.Glfw;

using Microsoft.Extensions.DependencyInjection;

using InputAction = KernelEngine.Framework.InputAction;

var services = new ServiceCollection()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddFlecsEcsRegistry()
    .AddEnkiTaskPool()
    .AddStdFileSystem()
    .AddPoolIo()
    .AddSingleton(_ => DemoInput.Build())
    .Add<IRuntime, Runtime>()
    .Add<IRuntimeModule>(new GlfwWindowModule(640, 160, "KernelEngine — 20 Input Actions (WASD, Space, Tab, Esc)"))
    .Add<IRuntimeModule>(new WebgpuRenderModule(shaderDir: ExamplePaths.ShaderDir, clearColor: new System.Numerics.Vector4(0.05f, 0.05f, 0.08f, 1.0f)))
    .Add<IRuntimeModule>(new FrameworkModule())
    .Add<IRuntimeModule>(new SceneNodesModule((host, _) =>
    {
        Console.WriteLine("[KernelEngine] Example: 20_input_actions");
        Console.WriteLine("[KernelEngine] Features: maps_built_in_code, map_priority, map_enabled");
        host.AddNode(new Player(), "Player");
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


static class DemoInput
{
    public static InputActions Build()
    {
        var actions = new InputActions();

        var system = actions.AddMap("System", 20);
        actions.BindKey(actions.AddAction(system, "ToggleMenu", NativeActionType.Button), Key.Tab);
        actions.BindKey(actions.AddAction(system, "Quit", NativeActionType.Button), Key.Escape);

        var menu = actions.AddMap("Menu", 10);
        actions.BindKey(actions.AddAction(menu, "Accept", NativeActionType.Button), Key.Space);
        actions.SetMapEnabled(menu, false);

        var gameplay = actions.AddMap("Gameplay", 0);
        actions.BindKeyQuad(actions.AddAction(gameplay, "Move", NativeActionType.Axis2d), Key.W, Key.S, Key.A, Key.D);
        actions.BindKey(actions.AddAction(gameplay, "Jump", NativeActionType.Button), Key.Space);
        return actions;
    }
}

sealed partial class Player : Node
{
    public partial InputAction Move { get; set; }
    public partial InputAction Jump { get; set; }
    public partial InputAction Accept { get; set; }
    public partial InputAction ToggleMenu { get; set; }
    public partial InputAction Quit { get; set; }
    public partial InputMap Menu { get; set; }

    public Player()
    {
        Move = "Move";
        Jump = "Jump";
        Accept = "Accept";
        ToggleMenu = "ToggleMenu";
        Quit = "Quit";
        Menu = "Menu";
    }

    void Update(in View view)
    {
        if (Quit.JustPressed) Environment.Exit(0);
        if (ToggleMenu.JustPressed)
        {
            var menu = Menu;
            menu.Enabled = !menu.Enabled;
            Console.WriteLine(menu.Enabled ? "[menu] opened: Space accepts, gameplay does not jump" : "[menu] closed");
        }
        if (Accept.JustPressed) Console.WriteLine("[menu] accept");
        if (Jump.JustPressed) Console.WriteLine("[gameplay] jump");
        if (Move.Vector != System.Numerics.Vector2.Zero) Console.WriteLine($"[gameplay] move {Move.Vector}");
    }
}
