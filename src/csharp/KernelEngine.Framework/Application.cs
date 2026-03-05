using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

public class Application : IDisposable
{
    public IServiceProvider Services { get; private set; } = null!;
    public Allocator Allocator { get; private set; } = null!;
    public Logger? Logger { get; private set; }
    public MessagePipe? MessagePipe { get; private set; }
    public Window Window { get; private set; } = null!;
    public Renderer Renderer { get; private set; } = null!;

    /// <summary>The current simulation world containing the Scene Graph and ECS Registry.</summary>
    public World ActiveWorld { get; set; } = null!;

    /// <summary>Called once after the world is created and before the main loop starts.</summary>
    public Action? OnReady { get; set; }

    /// <summary>Called every frame after <see cref="World.Update"/> and before <see cref="Window.PollEvents"/>.</summary>
    public Action? OnUpdate { get; set; }

    public void Run(IServiceCollection serviceCollection)
    {
        Services = serviceCollection.BuildServiceProvider();

        Allocator = Services.GetRequiredService<Allocator>();
        Logger = Services.GetService<Logger>();
        MessagePipe = Services.GetService<MessagePipe>();

        if (Logger != null)
        {
            foreach (var sink in Services.GetServices<ILoggerSink>())
                Logger.AddSink(sink, sink.MinLevel);
        }

        Window = Services.GetRequiredService<Window>();
        Renderer = Services.GetRequiredService<Renderer>();

        if (ActiveWorld == null)
            ActiveWorld = new World(Allocator, Renderer, Window);

        OnReady?.Invoke();

        while (!Window.ShouldClose())
        {
            MessagePipe?.Pump();
            ActiveWorld?.Update();
            OnUpdate?.Invoke();
            Renderer.Frame();
            Window.PollEvents();
        }
    }

    public virtual void Dispose()
    {
        ActiveWorld?.Dispose();
        (Services as IDisposable)?.Dispose();
    }
}
