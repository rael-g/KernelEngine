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

    public Input? Input { get; private set; }

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

        ResolveRequiredServices();
        Input = Services.GetService<Input>();

        if (ActiveWorld == null)
            ActiveWorld = new World(Allocator, Renderer, Window);

        LightNode.Initialize(ActiveWorld.Registry);
        PointLightNode.Initialize(ActiveWorld.Registry);
        SpotLightNode.Initialize(ActiveWorld.Registry);
        CameraNode.Initialize(ActiveWorld.Registry);
        MeshNode.ComponentId = ActiveWorld.MeshRendererComponentId;
        SkyboxNode.Initialize();
        // Handles 0 are built-in defaults created by the renderer during initialization.
        MeshNode.DefaultMeshHandle     = 0; // unit quad
        MeshNode.DefaultMaterialHandle = 0; // white material
        Renderer.SetAmbientLight(0.4f, 0.4f, 0.4f);
        ActiveWorld.AddSystem(new LightRenderSystem(Renderer));
        ActiveWorld.AddSystem(new CameraRenderSystem(Renderer, Window));
        ActiveWorld.AddSystem(new SkyboxRenderSystem(Renderer));    // after camera, before meshes
        ActiveWorld.AddSystem(new ShadowRenderSystem(Renderer));    // depth pass before scene
        ActiveWorld.AddSystem(new MeshRenderSystem(Renderer));

        OnReady?.Invoke();

        // ── DB-08: Native crash handling (SEH) ─────────────────────────────────
        NativeExceptionFilter.Register();

        try
        {
            while (!Window.ShouldClose())
            {
                ActiveWorld?.Update();
                OnUpdate?.Invoke();
                Renderer.Frame();
                Window.PollEvents();
                MessagePipe?.Pump();
            }
        }
        catch (Exception ex)
        {
            Logger?.Error("Application", $"Managed exception in main loop: {ex}");
            throw;
        }
    }

    // ── DB-08: P/Invoke for SEH ───────────────────────────────────────────────
    private static class NativeExceptionFilter
    {
        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        private static extern IntPtr SetUnhandledExceptionFilter(UnhandledExceptionFilter lpTopLevelExceptionFilter);

        private delegate int UnhandledExceptionFilter(IntPtr exceptionInfo);

        private static UnhandledExceptionFilter? _filter;

        public static void Register()
        {
            _filter = Filter;
            SetUnhandledExceptionFilter(_filter);
        }

        private static int Filter(IntPtr exceptionInfo)
        {
            // Simplified SEH extraction. In real world, we'd use ExceptionRecord struct.
            // exceptionInfo points to EXCEPTION_POINTERS
            // First member is ExceptionRecord pointer.
            // ExceptionCode is the first member of ExceptionRecord.
            int code = System.Runtime.InteropServices.Marshal.ReadInt32(
                System.Runtime.InteropServices.Marshal.ReadIntPtr(exceptionInfo));

            string name = code switch
            {
                unchecked((int)0x80000003) => "STATUS_BREAKPOINT (bgfx debug assert)",
                unchecked((int)0xC0000005) => "STATUS_ACCESS_VIOLATION",
                unchecked((int)0xC00000FD) => "STATUS_STACK_OVERFLOW",
                _ => $"0x{code:X8}"
            };

            Console.Error.WriteLine($"\n[FATAL] Native crash SEH {name}");
            Console.Error.Flush();
            Environment.Exit(1);
            return 0; // EXCEPTION_EXECUTE_HANDLER
        }
    }

    private void ResolveRequiredServices()
    {
        var missing = new List<(Type type, string hint)>
        {
            (typeof(Window),   "AddGlfwWindow(width, height, title)"),
            (typeof(Renderer), "AddBgfxRenderer(shaderPath)"),
        };

        var errors = missing
            .Where(e => Services.GetService(e.type) == null)
            .ToList();

        if (errors.Count > 0)
        {
            var lines = new System.Text.StringBuilder();
            lines.AppendLine("\n[STARTUP ERROR] Required services are not registered:");
            foreach (var (type, hint) in errors)
                lines.AppendLine($"  - {type.Name}  →  add .{hint}");
            lines.AppendLine("\nCheck your IServiceCollection setup in Program.cs.");
            var msg = lines.ToString();
            Console.Error.WriteLine(msg);
            Console.Error.Flush();
            Logger?.Error("Application", msg);
            throw new InvalidOperationException(msg);
        }

        Window   = Services.GetRequiredService<Window>();
        Renderer = Services.GetRequiredService<Renderer>();
    }

    public virtual void Dispose()
    {
        ActiveWorld?.Dispose();
        (Services as IDisposable)?.Dispose();
    }
}
