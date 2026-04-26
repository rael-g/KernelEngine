using System.Runtime.ExceptionServices;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;

namespace KernelEngine.Framework;

/// <summary>
/// Application shell: resolves services from DI, owns the frame loop, and coordinates three threads.
/// <list type="bullet">
///   <item><b>ke.main</b>   — window/OS thread: GLFW PollEvents, Input, MessagePipe pump.</item>
///   <item><b>ke.render</b> — renderer thread: on_initialize, SubmitPacket, Frame, on_shutdown.
///         All renderer API calls are pinned to this thread, making any backend work regardless
///         of whether it has internal threading support (OpenGL, DX11, bgfx single-thread, etc.).</item>
///   <item><b>ke.sim</b>    — simulation thread: World.Update, FrameSync producer.</item>
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

    /// <summary>Called once on ke.sim after ke.render is initialized and systems are registered.</summary>
    public Action? OnReady { get; set; }

    /// <summary>Called every sim frame after <see cref="World.Update"/>.</summary>
    public Action? OnUpdate { get; set; }

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

        // GLFW window must be created on the main thread.
        ValidateRequiredServices();
        Window   = Services.GetRequiredService<Window>();
        Input    = Services.GetService<Input>();
        Renderer = Services.GetRequiredService<Renderer>();

        if (ActiveWorld == null)
            ActiveWorld = new World(Allocator);

        InitializeSystems();

        _running = true;

        // ke.sim writes → ke.render reads.
        using var frameSync     = FrameSync.Create(Allocator, bufferCount: 2);
        using var renderReady   = new System.Threading.ManualResetEventSlim(false);

        Exception? renderException = null;
        Exception? simException    = null;

        // ke.render: owns every renderer API call for the lifetime of the app.
        using var renderThread = KernelThread.Create(Allocator, "ke.render", () =>
        {
            try
            {
                Renderer.Initialize();
                Renderer.SetAmbientLight(0.4f, 0.4f, 0.4f);
                renderReady.Set(); // signal ke.sim that the renderer is ready

                while (true)
                {
                    var packet = frameSync.BeginRead();
                    if (!_running) { packet.EndRead(); break; }

                    Renderer.SubmitPacket(packet);
                    Renderer.Frame();

                    packet.EndRead();
                }
            }
            catch (Exception ex)
            {
                renderException = ex;
                _running        = false;
                renderReady.Set(); // unblock ke.sim even on failure
            }
            finally
            {
                Renderer.Dispose();
            }
        });

        // ke.sim: drives the world and records into FramePackets.
        using var simThread = KernelThread.Create(Allocator, "ke.sim", () =>
        {
            try
            {
                renderReady.Wait(); // wait for ke.render to finish Initialize()
                if (!_running) return;

                OnReady?.Invoke();

                while (true)
                {
                    var packet = frameSync.BeginWrite();
                    if (!_running) { packet.EndWrite(); break; } // poison-pill
                    ActiveWorld?.Update(packet: packet);
                    OnUpdate?.Invoke();
                    packet.EndWrite();
                }
            }
            catch (Exception ex)
            {
                simException = ex;
                _running     = false;
                try { var p = frameSync.BeginWrite(); p.EndWrite(); } catch { }
            }
        });

        NativeExceptionFilter.Register();

        // ke.main: window and OS events only.
        try
        {
            while (_running)
            {
                Window.PollEvents();
                Input?.Update();
                MessagePipe?.Pump();

                if (Window.ShouldClose())
                    _running = false;
            }
        }
        catch (Exception ex)
        {
            Logger?.Error("Application", $"ke.main exception: {ex}");
            _running = false;
        }

        _running = false;
        simThread.Join();
        renderThread.Join();

        var ex1 = renderException;
        var ex2 = simException;
        if (ex1 != null) ExceptionDispatchInfo.Capture(ex1).Throw();
        if (ex2 != null) ExceptionDispatchInfo.Capture(ex2).Throw();
    }

    // ── Systems setup ─────────────────────────────────────────────────────────

    private unsafe void InitializeSystems()
    {
        LightNode.Initialize(ActiveWorld.Registry);
        PointLightNode.Initialize(ActiveWorld.Registry);
        SpotLightNode.Initialize(ActiveWorld.Registry);
        CameraNode.Initialize(ActiveWorld.Registry);
        MeshNode.Initialize(ActiveWorld.Registry);
        SkyboxNode.Initialize(ActiveWorld.Registry);

        MeshNode.DefaultMeshHandle     = 0;
        MeshNode.DefaultMaterialHandle = 0;

        var xformCid = ActiveWorld.TransformComponentId;

        var meshSystem   = new MeshRenderSystem(BgfxSystemDescFactory.CreateMeshSystemDesc(MeshNode.ComponentId, xformCid));
        var lightSystem  = new LightRenderSystem(BgfxSystemDescFactory.CreateLightSystemDesc(LightNode.ComponentId, PointLightNode.ComponentId, SpotLightNode.ComponentId, xformCid));
        var cameraSystem = new CameraRenderSystem(BgfxSystemDescFactory.CreateCameraSystemDesc(CameraNode.ComponentId, xformCid));
        var shadowSystem = new ShadowRenderSystem(BgfxSystemDescFactory.CreateShadowSystemDesc(Renderer.Native, LightNode.ComponentId, MeshNode.ComponentId, xformCid));
        var skyboxSystem = new SkyboxRenderSystem(BgfxSystemDescFactory.CreateSkyboxSystemDesc(SkyboxNode.ComponentId));

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

        var errors = missing.Where(e => Services.GetService(e.type) == null).ToList();

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

    // ── SEH crash filter ──────────────────────────────────────────────────────

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
        (Services as IDisposable)?.Dispose();
    }
}
