using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Application shell: resolves services from DI, creates the world, and runs the main loop.
/// </summary>
public class Application : IDisposable
{
    public IServiceProvider Services { get; private set; } = null!;
    public Allocator Allocator { get; private set; } = null!;
    public Logger? Logger { get; private set; }
    public MessagePipe? MessagePipe { get; private set; }
    public Window Window { get; private set; } = null!;
    public Renderer Renderer { get; private set; } = null!;

    /// <summary>The current simulation world containing the scene graph and ECS registry.</summary>
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

        LightNode.Initialize(ActiveWorld.Registry);
        PointLightNode.Initialize(ActiveWorld.Registry);
        SpotLightNode.Initialize(ActiveWorld.Registry);
        CameraNode.Initialize(ActiveWorld.Registry);
        MeshNode.Initialize(ActiveWorld.Registry);
        SkyboxNode.Initialize();
        // Handles 0 are built-in defaults created by the renderer during initialization.
        MeshNode.DefaultMeshHandle     = 0; // unit quad
        MeshNode.DefaultMaterialHandle = 0; // white material
        Renderer.SetAmbientLight(0.15f, 0.15f, 0.15f);
        ActiveWorld.AddSystem(new LightRenderSystem(Renderer));
        ActiveWorld.AddSystem(new CameraRenderSystem(Renderer, Window));
        ActiveWorld.AddSystem(new SkyboxRenderSystem(Renderer));    // after camera, before meshes
        ActiveWorld.AddSystem(new ShadowRenderSystem(Renderer));    // depth pass before scene
        ActiveWorld.AddSystem(new MeshRenderSystem(Renderer));

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
