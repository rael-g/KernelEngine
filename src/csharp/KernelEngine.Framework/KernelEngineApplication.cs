using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using KernelEngine.Core;
using KernelEngine.Core.Logging;
using KernelEngine.Core.Messaging;
using KernelEngine.Core.Allocators;

namespace KernelEngine.Framework;

public class KernelEngineApplication : IDisposable
{
    private readonly IHost _host;
    public IServiceProvider Services => _host.Services;

    public event Action? OnInitialize;
    public event Action? OnUpdate;
    public event Action? OnShutdown;

    public KernelEngineApplication(IHost host)
    {
        _host = host;
    }

    public void Run()
    {
        // 1. Start background services if any
        _host.Start();

        // 2. Resolve Engine Components
        var engine = Services.GetRequiredService<Engine>();
        var window = Services.GetRequiredService<IWindow>();
        var renderer = Services.GetRequiredService<IRenderer>();
        var logger = Services.GetService<NativeLogger>();
        var pipe = Services.GetService<NativeMessagePipe>();

        // 3. Register Sinks
        if (logger != null)
        {
            var sinks = Services.GetServices<ILoggerSink>();
            foreach (var sink in sinks)
            {
                logger.AddSink(sink.NativeSink);
            }
        }

        // 4. Register Systems in Engine
        engine.RegisterSystem(window);
        engine.RegisterSystem(renderer);

        // 5. Lifecycle
        OnInitialize?.Invoke();
        engine.Initialize();

        // 6. Main Loop (Runs on calling thread, usually Main Thread)
        while (!window.ShouldClose())
        {
            pipe?.Pump();
            OnUpdate?.Invoke();
            engine.Tick();
        }

        // 7. Cleanup
        OnShutdown?.Invoke();
        engine.Shutdown();
        
        _host.StopAsync().Wait();
    }

    public void Dispose()
    {
        _host.Dispose();
    }
}

public static class HostExtensions
{
    public static KernelEngineApplication AsKernelEngine(this IHost host)
    {
        return new KernelEngineApplication(host);
    }
}
