using System.Runtime.ExceptionServices;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;

namespace KernelEngine.Framework;

/// <summary>
/// Application shell: resolves services from DI, owns the frame loop, and coordinates threads.
/// <list type="bullet">
///   <item><b>ke.main</b> — bgfx API thread: bgfx::init, SubmitPacket, Frame, PollEvents, FrameSync consumer.</item>
///   <item><b>ke.sim</b>  — simulation thread: World.Update, FrameSync producer.</item>
/// </list>
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

    /// <summary>Called once on the sim thread after bgfx is initialized and systems are registered.</summary>
    public Action? OnReady { get; set; }

    /// <summary>Called every sim frame after <see cref="World.Update"/>.</summary>
    public Action? OnUpdate { get; set; }

    // Shared between main and ke.sim — volatile for visibility.
    private volatile bool _running;

    public void Run(IServiceCollection serviceCollection)
    {
        KernelThread.SetCurrentName("ke.main");

        Services = serviceCollection.BuildServiceProvider();

        Allocator   = Services.GetRequiredService<Allocator>();
        Logger      = Services.GetService<Logger>();
        MessagePipe = Services.GetService<MessagePipe>();

        if (Logger != null)
            foreach (var sink in Services.GetServices<ILoggerSink>())
                Logger.AddSink(sink, sink.MinLevel);

        // GLFW must be initialized on the main thread.
        ValidateRequiredServices();
        Window = Services.GetRequiredService<Window>();
        Input  = Services.GetService<Input>();

        if (ActiveWorld == null)
            ActiveWorld = new World(Allocator);

        // bgfx::init on ke.main — main thread is the bgfx API thread.
        Renderer = Services.GetRequiredService<Renderer>();
        Renderer.Initialize();

        InitializeSystems();

        _running = true;

        // Double-buffer handoff: ke.sim writes, ke.main reads.
        using var frameSync = FrameSync.Create(Allocator, bufferCount: 2);

        Exception? threadException = null;

        using var simThread = KernelThread.Create(Allocator, "ke.sim", () =>
        {
            try
            {
                OnReady?.Invoke();

                while (_running)
                {
                    var packet = frameSync.BeginWrite();
                    ActiveWorld?.Update(packet: packet);
                    OnUpdate?.Invoke();
                    packet.EndWrite();
                }

                // Poison-pill: unblocks main's BeginRead so it can exit cleanly.
                var poison = frameSync.BeginWrite();
                poison.EndWrite();
            }
            catch (Exception ex)
            {
                threadException = ex;
                _running        = false;
                try { var p = frameSync.BeginWrite(); p.EndWrite(); } catch { }
            }
        });

        NativeExceptionFilter.Register();

        try
        {
            while (true)
            {
                var packet = frameSync.BeginRead();

                if (!_running)
                {
                    packet.EndRead();
                    break;
                }

                // bgfx API thread: submit draw calls then present.
                Renderer.SubmitPacket(packet);
                Renderer.Frame();

                Window.PollEvents();
                Input?.Update();
                MessagePipe?.Pump();

                if (Window.ShouldClose())
                    _running = false;

                packet.EndRead();
            }
        }
        catch (Exception ex)
        {
            Logger?.Error("Application", $"Main-thread exception: {ex}");
            _running = false;
        }

        _running = false;
        simThread.Join();

        if (threadException != null)
            ExceptionDispatchInfo.Capture(threadException).Throw();
    }

    // ── Systems setup ─────────────────────────────────────────────────────────

    private void InitializeSystems()
    {
        LightNode.Initialize(ActiveWorld.Registry);
        PointLightNode.Initialize(ActiveWorld.Registry);
        SpotLightNode.Initialize(ActiveWorld.Registry);
        CameraNode.Initialize(ActiveWorld.Registry);
        MeshNode.Initialize(ActiveWorld.Registry);
        SkyboxNode.Initialize(ActiveWorld.Registry);

        MeshNode.DefaultMeshHandle     = 0; // unit quad (built-in)
        MeshNode.DefaultMaterialHandle = 0; // white material (built-in)

        Renderer.SetAmbientLight(0.4f, 0.4f, 0.4f);

        var xformCid = ActiveWorld.TransformComponentId;

        // Phase 4: Create native system descriptors via bgfx factory (lives in the bgfx plugin layer).
        var meshSystem   = new MeshRenderSystem(BgfxSystemDescFactory.CreateMeshSystemDesc(MeshNode.ComponentId, xformCid));
        var lightSystem  = new LightRenderSystem(BgfxSystemDescFactory.CreateLightSystemDesc(LightNode.ComponentId, PointLightNode.ComponentId, SpotLightNode.ComponentId, xformCid));
        var cameraSystem = new CameraRenderSystem(BgfxSystemDescFactory.CreateCameraSystemDesc(CameraNode.ComponentId, xformCid));
        var shadowSystem = new ShadowRenderSystem(BgfxSystemDescFactory.CreateShadowSystemDesc(LightNode.ComponentId, MeshNode.ComponentId, xformCid));
        var skyboxSystem = new SkyboxRenderSystem(BgfxSystemDescFactory.CreateSkyboxSystemDesc(SkyboxNode.ComponentId));

        // Register Native parts in Kernel for parallel execution
        ActiveWorld.AddSystem(meshSystem.NativeDescriptor);
        ActiveWorld.AddSystem(lightSystem.NativeDescriptor);
        ActiveWorld.AddSystem(cameraSystem.NativeDescriptor);
        ActiveWorld.AddSystem(shadowSystem.NativeDescriptor);
        ActiveWorld.AddSystem(skyboxSystem.NativeDescriptor);

        // Register Managed parts (NO-OP wrappers)
        ActiveWorld.AddSystem(meshSystem);
        ActiveWorld.AddSystem(lightSystem);
        ActiveWorld.AddSystem(cameraSystem);
        ActiveWorld.AddSystem(shadowSystem);
        ActiveWorld.AddSystem(skyboxSystem);
    }

    // ── Service validation ────────────────────────────────────────────────────

    private void ValidateRequiredServices()
    {
        var missing = new List<(Type type, string hint)>
        {
            (typeof(Window),   "AddGlfwWindow(width, height, title)"),
            (typeof(Renderer), "AddBgfxRenderer(shaderPath)"),
        };

        var errors = missing
            .Where(e => Services.GetService(e.type) == null)
            .ToList();

        if (errors.Count == 0) return;

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

    // ── DB-08: SEH crash filter ───────────────────────────────────────────────

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
            return 0;
        }
    }

    public virtual void Dispose()
    {
        ActiveWorld?.Dispose();
        Renderer?.Dispose();
        (Services as IDisposable)?.Dispose();
    }
}
