using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Core;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;
using KernelEngine.Core.Messaging;

namespace KernelEngine.Framework;

public abstract class Application : IDisposable
{
    protected IServiceProvider Services { get; private set; } = null!;
    protected Engine Engine { get; private set; } = null!;
    protected IAllocator Allocator { get; private set; } = null!;
    protected NativeLogger? Logger { get; private set; }
    protected NativeMessagePipe? MessagePipe { get; private set; }
    protected IWindow Window { get; private set; } = null!;
    protected IRenderer Renderer { get; private set; } = null!;

    public void Run(IServiceCollection serviceCollection)
    {
        // 1. Build Provider
        Services = serviceCollection.BuildServiceProvider();

        // 2. Resolve Core
        Allocator = Services.GetRequiredService<IAllocator>();
        Logger = Services.GetService<NativeLogger>();
        MessagePipe = Services.GetService<NativeMessagePipe>();
        Engine = Services.GetRequiredService<Engine>();

        // Register all sinks to the native logger
        if (Logger != null)
        {
            var sinks = Services.GetServices<ILoggerSink>();
            foreach (var sink in sinks)
            {
                Logger.AddSink(sink.NativeSink);
            }
        }

        // 3. Resolve Domain Systems
        Window = Services.GetRequiredService<IWindow>();
        Renderer = Services.GetRequiredService<IRenderer>();

        // 4. Manual Wiring (Engine needs the systems)
        Engine.RegisterSystem(Window);
        Engine.RegisterSystem(Renderer);

        // 5. Lifecycle
        OnInitialize();
        Engine.Initialize();

        while (!Window.ShouldClose())
        {
            MessagePipe?.Pump();
            OnUpdate();
            Engine.Tick();
        }

        OnShutdown();
        Engine.Shutdown();
    }

    protected virtual void OnInitialize() { }
    protected virtual void OnUpdate() { }
    protected virtual void OnShutdown() { }

    public virtual void Dispose()
    {
        // The ServiceProvider handles disposal of registered singletons
        (Services as IDisposable)?.Dispose();
    }
}
