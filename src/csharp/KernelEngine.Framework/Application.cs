using System.Runtime.ExceptionServices;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Application shell: resolves services from DI, owns the frame loop, and coordinates threads.
/// <list type="bullet">
///   <item><b>ke.main</b> — platform loop: PollEvents, Input, MessagePipe, FrameSync consumer.</item>
///   <item><b>ke.sim</b>  — bgfx API thread: bgfx::init, World.Update, Renderer.Frame, FrameSync producer.</item>
/// </list>
/// Phase 3 will split ke.sim into pure sim + a dedicated render thread that reads the FrameSync packet.
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

        _running = true;

        // Double-buffer handoff: ke.sim writes, ke.main reads (Phase 3 will fill the packets).
        using var frameSync = FrameSync.Create(Allocator, bufferCount: 2);

        Exception? threadException = null;

        using var simThread = KernelThread.Create(Allocator, "ke.sim", () =>
        {
            try
            {
                // Resolve Renderer here so bgfx::init runs on ke.sim (bgfx API thread).
                var renderer = Services.GetRequiredService<Renderer>();
                renderer.Initialize();
                Renderer = renderer;

                InitializeSystems();
                OnReady?.Invoke();

                while (_running)
                {
                    var packet = frameSync.BeginWrite();
                    ActiveWorld?.Update();
                    OnUpdate?.Invoke();
                    Renderer.Frame();   // bgfx::frame — must be on the API thread (ke.sim)
                    packet.EndWrite();
                }

                // Poison-pill write: unblocks main's BeginRead so it can exit cleanly.
                var poison = frameSync.BeginWrite();
                poison.EndWrite();

                // bgfx::shutdown must be on the API thread.
                Renderer.Dispose();
                Renderer = null!;
            }
            catch (Exception ex)
            {
                threadException = ex;
                _running        = false;
                // Ensure main is not stuck on BeginRead.
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

                // Phase 3: FrameSubmitter reads the packet and calls bgfx draw calls here.

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
        SkyboxNode.Initialize();

        MeshNode.DefaultMeshHandle     = 0; // unit quad (built-in)
        MeshNode.DefaultMaterialHandle = 0; // white material (built-in)

        Renderer.SetAmbientLight(0.4f, 0.4f, 0.4f);
        ActiveWorld.AddSystem(new LightRenderSystem(Renderer));
        ActiveWorld.AddSystem(new CameraRenderSystem(Renderer, Window));
        ActiveWorld.AddSystem(new SkyboxRenderSystem(Renderer));
        ActiveWorld.AddSystem(new ShadowRenderSystem(Renderer));
        ActiveWorld.AddSystem(new MeshRenderSystem(Renderer));
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
        // Renderer was disposed on ke.sim (bgfx API thread) — skip here.
        (Services as IDisposable)?.Dispose();
    }
}
