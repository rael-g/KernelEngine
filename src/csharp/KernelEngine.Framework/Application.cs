using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Application shell: resolves services from DI, owns the frame loop, and coordinates three threads.
/// <list type="bullet">
///   <item><b>ke.main</b>   — window/OS thread: window PollEvents, Input snapshotting.</item>
///   <item><b>ke.render</b> — renderer thread: Initialize, SubmitPacket, Frame, Dispose.
///         All renderer API calls are pinned to this thread, making any backend work regardless
///         of whether it has internal threading support (OpenGL, DX11, bgfx single-thread, etc.).</item>
///   <item><b>ke.sim</b>    — simulation thread: World.Update, FrameSync producer.</item>
/// </list>
/// </summary>
public class Application : IDisposable
{
    public IServiceProvider Services { get; private set; } = null!;
    public IAllocator Allocator { get; private set; } = null!;
    public ILogger? Logger { get; private set; }
    public IWindow Window { get; private set; } = null!;
    public IRenderer Renderer { get; private set; } = null!;
    public IInput? Input { get; private set; }
    public IDevPlatform? DevPlatform { get; private set; }

    private IKernelFactory _kernelFactory = null!;
    private IProxyAllocator? _proxyAllocator;

    /// <summary>The current simulation world containing the scene graph and ECS registry.</summary>
    public IWorld ActiveWorld { get; set; } = null!;

    private Scene? _scene;

    /// <summary>The scene graph facade for <see cref="ActiveWorld"/>.</summary>
    public Scene Scene => _scene ??= new Scene(ActiveWorld);

    /// <summary>Called once on ke.sim after ke.render is initialized and systems are registered.</summary>
    public Action<IResourceFactory>? OnReady { get; set; }

    /// <summary>Called every sim frame after <c>IWorld.Update</c>.</summary>
    public Action<ISceneWriter, IInputReader>? OnUpdate { get; set; }

    private readonly CancellationTokenSource _cts = new();
    private IInputBuffer _inputBuffer = null!;
    private IResourceCommandQueue _resourceQueue = null!;
    private ShadowRenderSystem? _shadowSystem;

    private string GetGpuFatalError()
    {
        try
        {
            return Renderer.GetLastFatalError() ?? "Unknown GPU fatal error";
        }
        catch
        {
            return "Failed to retrieve GPU fatal error message";
        }
    }

    private void CheckResult(Result res, string context)
    {
        if (res == KernelResult.GpuFatal)
            throw new KernelException(res, context, GetGpuFatalError());
        res.ThrowIfFailed();
    }

    /// <summary>
    /// Asks <see cref="DevPlatform"/> (when available) to publish the current thread's name to the OS,
    /// making it visible in debuggers and profilers. No-op when DevPlatform is not registered.
    /// </summary>
    private void SetOsThreadName(string name) => DevPlatform?.SetOsThreadName(name);

    public void Run(IServiceCollection serviceCollection)
    {
        Services = serviceCollection.BuildServiceProvider();

        _kernelFactory = Services.GetRequiredService<IKernelFactory>();
        _kernelFactory.SetCurrentThreadName("ke.main");

        var baseAllocator = Services.GetRequiredService<IAllocator>();
        _proxyAllocator = _kernelFactory.CreateProxyAllocator(baseAllocator, "ApplicationRoot");
        Allocator = _proxyAllocator;

        Logger = Services.GetService<ILogger>();

        if (Logger != null)
            foreach (var sink in Services.GetServices<ILoggerSink>())
                Logger.AddSink(sink, sink.MinLevel);

        // GLFW window must be created on the main thread.
        ValidateRequiredServices();
        Window      = Services.GetRequiredService<IWindow>();
        Input       = Services.GetService<IInput>();
        Renderer    = Services.GetRequiredService<IRenderer>();
        DevPlatform = Services.GetService<IDevPlatform>(); // optional dev-only diagnostics

        ActiveWorld ??= _kernelFactory.CreateWorld(Allocator);

        _inputBuffer   = new InputBuffer();
        _resourceQueue = new ResourceCommandQueue(_kernelFactory);

        InitializeSystems();

        // ke.sim writes → ke.render reads.
        using var frameSync     = _kernelFactory.CreateFrameSync(Allocator, bufferCount: 2);
        using var renderReady   = new System.Threading.ManualResetEventSlim(false);
        using var simReady      = new System.Threading.ManualResetEventSlim(false);

        NativeExceptionFilter.Register(Logger);

        Exception? renderException = null;
        Exception? simException    = null;

        // OS-visible name for ke.main (TLS name was set at the top via SetCurrentName).
        SetOsThreadName("ke.main");

        // ke.render: owns every renderer API call for the lifetime of the app.
        using var renderThread = _kernelFactory.CreateThread(Allocator, "ke.render", DevPlatform, () =>
        {
            try
            {
                Logger?.Info("Application", "ke.render: initializing renderer");
                Renderer.Initialize();
                Renderer.SetAmbientLight(0.4f, 0.4f, 0.4f);

                // Create the shadow map on ke.render (GPU creation requires this thread).
                if (_shadowSystem != null)
                {
                    var shadowMap = Renderer.CreateShadowMap(1024, 1024);
                    if (shadowMap.IsOk)
                    {
                        _shadowSystem.SetShadowMap(shadowMap.Value);
                        Logger?.Info("Application", "ke.render: shadow map created (1024x1024)");
                    }
                }

                Logger?.Info("Application", "ke.render: renderer ready — signaling ke.sim");
                renderReady.Set(); // signal ke.sim that the renderer is ready

                // Drain resource commands produced by ke.sim's OnReady before entering
                // the frame loop — otherwise BeginRead blocks while ke.sim blocks on
                // CreateMaterial/CreateMesh (deadlock).
                while (!simReady.IsSet && !_cts.IsCancellationRequested)
                {
                    _resourceQueue.Drain(Renderer);
                    System.Threading.Thread.SpinWait(100);
                }
                _resourceQueue.Drain(Renderer); // final drain after simReady

                Logger?.Info("Application", "ke.render: entering frame loop");
                bool firstFrame = true;
                while (!_cts.IsCancellationRequested)
                {
                    _resourceQueue.Drain(Renderer);

                    var packet = frameSync.BeginRead();
                    if (_cts.IsCancellationRequested) { packet.EndRead(); break; }

                    CheckResult(Renderer.SubmitPacket(packet), "Renderer.SubmitPacket");
                    CheckResult(Renderer.Frame(), "Renderer.Frame");

                    packet.EndRead();

                    if (firstFrame)
                    {
                        Logger?.Info("Application", "ke.main: first frame rendered");
                        firstFrame = false;
                    }
                }
            }
            catch (Exception ex)
            {
                renderException = ex;
                Logger?.Error("Application", $"ke.render fatal exception: {ex.Message}");
                _cts.Cancel();
                renderReady.Set(); // unblock ke.sim even on failure
                simReady.Set();    // unblock ke.render's OnReady drain loop
            }
            finally
            {
                Renderer.Dispose();
            }
        });

        // ke.sim: drives the world and records into FramePackets.
        using var simThread = _kernelFactory.CreateThread(Allocator, "ke.sim", DevPlatform, () =>
        {
            try
            {
                renderReady.Wait(); // wait for ke.render to finish Initialize()
                if (_cts.IsCancellationRequested) return;

                var factory = _resourceQueue.CreateFactory();
                OnReady?.Invoke(factory);
                Logger?.Info("Application", "ke.sim: OnReady complete — entering frame loop");
                simReady.Set(); // signal ke.render that OnReady is complete

                while (!_cts.IsCancellationRequested)
                {
                    var packet = frameSync.BeginWrite();
                    if (_cts.IsCancellationRequested) { packet.EndWrite(); break; } // poison-pill

                    var input = _inputBuffer.Consume();
                    var writer = new FramePacketSceneWriter(packet, _kernelFactory);

                    ActiveWorld?.Update(packet: packet, input: input);
                    OnUpdate?.Invoke(writer, input);

                    packet.EndWrite();
                }
            }
            catch (Exception ex)
            {
                simException = ex;
                Logger?.Error("Application", $"ke.sim fatal exception: {ex.Message}");
                _cts.Cancel();
                // Signal ke.render to exit BeginRead if it's waiting
                try { var p = frameSync.BeginWrite(); p.EndWrite(); } catch { }
            }
        });

        NativeExceptionFilter.Register(Logger);

        // ke.main: window and OS events only.
        try
        {
            while (!_cts.IsCancellationRequested)
            {
                // Update clears last frame's pressed/released before events fire.
                Input?.Update();
                Window.PollEvents();
                if (Input != null)
                    _inputBuffer.Produce(Input.CaptureSnapshot());

                if (Window.ShouldClose())
                    _cts.Cancel();
            }
        }
        catch (Exception ex)
        {
            Logger?.Error("Application", $"ke.main exception: {ex}");
            _cts.Cancel();
        }

        // Wait for threads to exit with timeout
        if (!simThread.Join(5000))
            Logger?.Error("Application", "ke.sim did not stop within 5s — forcing exit");

        if (!renderThread.Join(3000))
            Logger?.Error("Application", "ke.render did not stop within 3s — forcing exit");

        var ex1 = renderException;
        var ex2 = simException;
        if (ex1 != null)
        {
            Logger?.Critical("Application", $"Terminating due to ke.render crash: {ex1.Message}");
            Logger?.Flush();
            ExceptionDispatchInfo.Capture(ex1).Throw();
        }
        if (ex2 != null)
        {
            Logger?.Critical("Application", $"Terminating due to ke.sim crash: {ex2.Message}");
            Logger?.Flush();
            ExceptionDispatchInfo.Capture(ex2).Throw();
        }
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

        MeshNode.DefaultMeshHandle     = new(0);
        MeshNode.DefaultMaterialHandle = new(0);

        var xformCid = ActiveWorld.TransformComponentId;

        // All render systems are pure-managed now — render/core C++ is no longer in the pipeline.
        ActiveWorld.AddSystem(new CameraRenderSystem(CameraNode.ComponentId, xformCid));
        ActiveWorld.AddSystem(new LightRenderSystem(
            LightNode.ComponentId, PointLightNode.ComponentId, SpotLightNode.ComponentId, xformCid));
        ActiveWorld.AddSystem(new MeshRenderSystem(MeshNode.ComponentId, xformCid));
        ActiveWorld.AddSystem(new SkyboxRenderSystem(SkyboxNode.ComponentId));

        _shadowSystem = new ShadowRenderSystem(LightNode.ComponentId, MeshNode.ComponentId, xformCid);
        ActiveWorld.AddSystem(_shadowSystem);
    }

    // ── Service validation ────────────────────────────────────────────────────

    private void ValidateRequiredServices()
    {
        var missing = new List<(Type type, string hint)>
        {
            (typeof(IWindow),   "AddGlfwWindow() or equivalent"),
            (typeof(IRenderer), "AddBgfxRenderer() or equivalent"),
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
        [DllImport("kernel32.dll")]
        private static extern IntPtr SetUnhandledExceptionFilter(UnhandledExceptionFilter lpTopLevelExceptionFilter);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentProcessId();

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport("dbghelp.dll", SetLastError = true)]
        private static extern bool MiniDumpWriteDump(
            IntPtr hProcess,
            uint processId,
            IntPtr hFile,
            uint dumpType,
            IntPtr exceptionParam,
            IntPtr userStreamParam,
            IntPtr callbackParam);

        private delegate int UnhandledExceptionFilter(IntPtr exceptionInfo);

        private static UnhandledExceptionFilter? _filter;
        private static ILogger? _staticLogger;

        public static void Register(ILogger? logger)
        {
            _staticLogger = logger;
            _filter = Filter;
            SetUnhandledExceptionFilter(_filter);
        }

        private static int Filter(IntPtr exceptionInfo)
        {
            int code = Marshal.ReadInt32(Marshal.ReadIntPtr(exceptionInfo));

            // 0xE0434352 ('MCR\E0') is the CLR managed-exception SEH code.
            // Returning 0 (EXCEPTION_CONTINUE_SEARCH) lets the CLR unwind it normally.
            if (code == unchecked((int)0xE0434352)) return 0;

            string name = code switch
            {
                unchecked((int)0x80000003) => "STATUS_BREAKPOINT (bgfx debug assert)",
                unchecked((int)0xC0000005) => "STATUS_ACCESS_VIOLATION",
                unchecked((int)0xC00000FD) => "STATUS_STACK_OVERFLOW",
                _ => $"0x{code:X8}"
            };

            string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            string dumpPath = Path.GetFullPath($"crash_{timestamp}.dmp");

            try
            {
                using var fs = new FileStream(dumpPath, FileMode.Create, FileAccess.Write, FileShare.None);

                // MINI_DUMP_TYPE flags:
                // 0x00000000 = MiniDumpNormal
                // 0x00000004 = MiniDumpWithHandleData
                // 0x00000020 = MiniDumpWithUnloadedModules
                // 0x00001000 = MiniDumpWithThreadInfo
                uint dumpType = 0x00000000 | 0x00000004 | 0x00000020 | 0x00001000;

                var exceptionPointers = Marshal.AllocHGlobal(Marshal.SizeOf<MINIDUMP_EXCEPTION_INFORMATION>());
                try
                {
                    var mei = new MINIDUMP_EXCEPTION_INFORMATION
                    {
                        ThreadId          = GetCurrentThreadId(),
                        ExceptionPointers = exceptionInfo,
                        ClientPointers    = false
                    };
                    Marshal.StructureToPtr(mei, exceptionPointers, false);

                    bool success = MiniDumpWriteDump(
                        GetCurrentProcess(),
                        GetCurrentProcessId(),
                        fs.SafeFileHandle.DangerousGetHandle(),
                        dumpType,
                        exceptionPointers,
                        IntPtr.Zero,
                        IntPtr.Zero);

                    if (success)
                        Console.Error.WriteLine($"\n[FATAL] Native crash SEH {name}\nCrash dump written to: {dumpPath}");
                    else
                        Console.Error.WriteLine($"\n[FATAL] Native crash SEH {name}\nFailed to write crash dump (Error {Marshal.GetLastWin32Error()})");
                }
                finally
                {
                    Marshal.FreeHGlobal(exceptionPointers);
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"\n[FATAL] Native crash SEH {name}\nFailed to generate crash dump: {ex.Message}");
            }

            _staticLogger?.Critical("Application", $"PROCESS TERMINATING DUE TO NATIVE CRASH {name}");
            _staticLogger?.Flush();

            Console.Error.Flush();
            Environment.Exit(1);
            return 0;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        private struct MINIDUMP_EXCEPTION_INFORMATION
        {
            public uint   ThreadId;
            public IntPtr ExceptionPointers;
            public bool   ClientPointers;
        }
    }

    public virtual void Dispose()
    {
        _cts.Dispose();
        ActiveWorld?.Dispose();

        _proxyAllocator?.Report(Logger);

        (Services as IDisposable)?.Dispose();
        _proxyAllocator?.Dispose();
    }
}
