using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

public abstract class Application : IDisposable
{
    protected IServiceProvider Services { get; private set; } = null!;
    protected Allocator Allocator { get; private set; } = null!;
    protected Logger? Logger { get; private set; }
    protected MessagePipe? MessagePipe { get; private set; }
    protected Window Window { get; private set; } = null!;
    protected Renderer Renderer { get; private set; } = null!;

    /// <summary>
    /// The current simulation world containing the Scene Graph and ECS Registry.
    /// Can be swapped at runtime to change scenes.
    /// </summary>
    public World ActiveWorld { get; set; } = null!;

    public void Run(IServiceCollection serviceCollection)
    {
        // 1. Build Provider
        Services = serviceCollection.BuildServiceProvider();

        // 2. Resolve Core
        Allocator = Services.GetRequiredService<Allocator>();
        Logger = Services.GetService<Logger>();
        MessagePipe = Services.GetService<MessagePipe>();

        // Register all sinks to the native logger
        if (Logger != null)
        {
            var sinks = Services.GetServices<ILoggerSink>();
            foreach (var sink in sinks)
            {
                Logger.AddSink(sink);
            }
        }

        // 3. Resolve Domain Services
        Window = Services.GetRequiredService<Window>();
        Renderer = Services.GetRequiredService<Renderer>();

        // 4. Initialize World if not set by user before Run
        if (ActiveWorld == null)
        {
            ActiveWorld = new World(Allocator, Renderer, Window);
        }

        // 5. User setup hook — add nodes, load assets, etc.
        OnReady();

        // 6. Main Loop
        while (!Window.ShouldClose())
        {
            MessagePipe?.Pump();
            ActiveWorld?.Update();
            OnUpdate();
            Window.PollEvents();
        }
    }

    /// <summary>
    /// Called once after the world is created and before the main loop starts.
    /// Override to populate the scene, load assets, or configure initial state.
    /// </summary>
    protected virtual void OnReady() { }

    /// <summary>Called every frame after <see cref="World.Update"/> and before <see cref="Window.PollEvents"/>.</summary>
    protected virtual void OnUpdate() { }

    public virtual void Dispose()
    {
        ActiveWorld?.Dispose();
        (Services as IDisposable)?.Dispose();
    }
}
