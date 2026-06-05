using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

// ── 00 Input Test ─────────────────────────────────────────────────────────────
// Validates the input event pipeline (kernel ring buffer → cross-thread queue →
// tree dispatch → node OnInputEvent). Mouse-cursor position is continuous state
// and is read via polling in OnUpdate — it is intentionally NOT an event.
//
// Click the window first so it has keyboard focus, then:
//   • Tap any key                  → "KEY DOWN ... / UP ..."
//   • Click any mouse button       → "BUTTON DOWN ... / UP ..."
//   • Scroll the wheel             → "SCROLL dx=... dy=..."
//   • Move the cursor              → live "POS x=... y=..." line
//   • Escape                       → quit

var services = new ServiceCollection()
    .AddKernel().AddNativeFramework()
    .AddLogger()
    .AddConsoleSink()
    .AddInput()
    .AddGlfwWindow(640, 160, "KernelEngine — 00 Input Test (click window, then type)")
    .AddBgfxRenderer(System.IO.Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

// Root listener: receives every event the tree dispatches, before any descendant.
app.OnReady = _ =>
{
    var listener = app.Tree.AddNode(new Listener(), "InputListener");
    return Task.CompletedTask;
};

app.OnUpdate = (tree, input) =>
{
    tree.ClearColor(0.05f, 0.05f, 0.08f, 1f);

    // Mouse position is continuous state, not an event — read it via the snapshot.
    var p = input.MousePosition;
    Console.Write($"\rPOS x={p.X,6:F1} y={p.Y,6:F1}    ");
};

app.Run(services);

sealed class Listener : Node
{
    protected override void OnInput(ref InputEvent evt)
    {
        switch (evt.Kind)
        {
            case InputEventKind.KeyDown:
                Console.WriteLine($"\nKEY DOWN  {evt.Key}");
                if (evt.Key == Key.Escape) Environment.Exit(0);
                break;
            case InputEventKind.KeyUp:
                Console.WriteLine($"\nKEY UP    {evt.Key}");
                break;
            case InputEventKind.MouseButtonDown:
                Console.WriteLine($"\nBUTTON DOWN  {evt.Button}");
                break;
            case InputEventKind.MouseButtonUp:
                Console.WriteLine($"\nBUTTON UP    {evt.Button}");
                break;
            case InputEventKind.MouseScroll:
                Console.WriteLine($"\nSCROLL dx={evt.Scroll.X:F1} dy={evt.Scroll.Y:F1}");
                break;
        }
    }
}
