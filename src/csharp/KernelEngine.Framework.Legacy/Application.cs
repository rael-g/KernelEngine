using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework.Legacy;

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

    private IKernelFactory _kernelFactory = null!;
    private IProxyAllocator? _proxyAllocator;

    /// <summary>The current simulation world (ECS). Engine-internal — game code uses <see cref="Tree"/>.</summary>
    internal IWorld ActiveWorld
    {
        get => _world;
        set
        {
            if (_world == value) return;
            _world = value;
            _scene = null; // Invalidate cached tree façade
        }
    }

    private IWorld _world = null!;
    private Tree? _scene;

    /// <summary>The Tree graph facade for <see cref="ActiveWorld"/>.</summary>
    public Tree Tree => _scene ??= new Tree(
        ActiveWorld,
        FrameworkBackends.Required,
        Services);

    /// <summary>
    /// Called once on ke.sim after ke.render is initialized and systems are registered.
    /// The frame loop does not start until the returned <see cref="Task"/> completes —
    /// safe to <c>await</c> resource creation here without racing the first tick.
    /// </summary>
    public Func<IResourceFactory, Task>? OnReady { get; set; }

    /// <summary>
    /// High-level ref-counted GPU resource manager (Phase 1 of the resource pipeline). Valid from
    /// the start of <see cref="OnReady"/> onward. Prefer this over the raw <see cref="IResourceFactory"/>
    /// for new code — its <c>CreateXAsync</c> methods don't block ke.sim and produce
    /// <see cref="Material"/>/<see cref="Mesh"/>/<see cref="Texture"/> with managed lifetime.
    /// </summary>
    public ResourceManager Resources { get; private set; } = null!;

    /// <summary>
    /// Load-from-path façade with cache + dedup (Phase 2). Non-null when an <see cref="IAssetLoader"/>
    /// is registered (e.g. via <c>AddAssimpAssetLoader()</c>); otherwise null. Same path → same
    /// ref-counted instance (a fresh reference; release like any resource).
    /// </summary>
    public Assets? Assets { get; private set; }

    /// <summary>Called every sim frame after <c>IWorld.Update</c>.</summary>
    public Action<ISceneWriter, IInputReader>? OnUpdate { get; set; }

    private readonly CancellationTokenSource _cts = new();
    private IInputBuffer _inputBuffer = null!;
    private readonly InputEventBuffer _eventBuffer = new();
    private readonly InputEvent[] _eventStaging = new InputEvent[256];
    private readonly List<InputActionEvent> _actionEventBuffer = new(32);
    private IResourceCacheBackend? _meshCache;
    private IResourceCacheBackend? _materialCache;
    private IResourceCacheBackend? _textureCache;
    private IAssetResolverBackend? _assetResolver;
    private ISceneTree? _sceneTree;

    private System.Numerics.Vector4? _projectClearColor;
    private System.Numerics.Vector3? _projectAmbientLight;
    private IResourceCommandQueue _resourceQueue = null!;
    private ShadowRenderSystem? _shadowSystem;
    private Physics2DSystem? _physics2DSystem;

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
    /// Sets the calling thread's name on both the kernel-side TLS (for ke_thread_assert_current
    /// from C plugins) and on the .NET runtime side (which since .NET 6 propagates the name to
    /// the OS — Win32 SetThreadDescription / pthread_setname_np — making it visible in
    /// debuggers and profilers).
    /// </summary>
    private static void SetThreadName(string name)
    {
        System.Threading.Thread.CurrentThread.Name = name;
        KernelEngine.Kernel.KernelThread.SetCurrentName(name);
    }

    public void Run(IServiceCollection serviceCollection)
    {
        // Register late-bound singletons that Application creates during sim init (after the
        // ServiceProvider is built). The factories close over `this` and resolve to the live
        // instance — so node ctors that take Assets/ResourceManager via DI (e.g. Pong's
        // Scoreboard) just work without manual wiring.
        serviceCollection.AddSingleton<IWorld>(_ => ActiveWorld
            ?? throw new InvalidOperationException(
                "IWorld is null — resolved before Application.Run finished initializing."));
        serviceCollection.AddSingleton<ISceneTree>(_ => (ISceneTree)Tree);
        serviceCollection.AddSingleton(_ => Assets
            ?? throw new InvalidOperationException(
                "Assets is null. Either no asset loader is registered (.AddStbImageLoader / .AddAssimpAssetLoader / .AddTextStbTrueType) or the service was resolved before sim init reached OnReady."));
        serviceCollection.AddSingleton(_ => Resources
            ?? throw new InvalidOperationException(
                "ResourceManager is null — resolved before sim init reached OnReady."));

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

        ActiveWorld ??= _kernelFactory.CreateWorld(Allocator);

        _inputBuffer   = new InputBuffer();
        _resourceQueue = FrameworkBackends.Required.CreateResourceQueue();

        InitializeSystems();

        // ke.sim writes → ke.render reads.
        using var frameSync     = _kernelFactory.CreateFrameSync(Allocator, bufferCount: 2);
        using var renderReady   = new System.Threading.ManualResetEventSlim(false);
        using var simReady      = new System.Threading.ManualResetEventSlim(false);

        NativeExceptionFilter.Register(Logger);

        Exception? renderException = null;
        Exception? simException    = null;

        // ke.main: kernel TLS + .NET name (which propagates to the OS on .NET 6+).
        SetThreadName("ke.main");

        // ke.render: owns every renderer API call for the lifetime of the app.
        var renderThread = new System.Threading.Thread(() =>
        {
            SetThreadName("ke.render");
            try
            {
                Logger?.Info("Application", "ke.render: initializing renderer");
                Renderer.Initialize();
                // Capture the backend's clip-space convention so the matrix builders target it.
                // Set before ke.sim's first frame (which happens after renderReady below).
                Internal.ViewProjection.SetConvention(Renderer.GetNdcConvention());
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
        }) { Name = "ke.render", IsBackground = false };
        renderThread.Start();

        // ke.sim: drives the world and records into FramePackets.
        var simThread = new System.Threading.Thread(() =>
        {
            SetThreadName("ke.sim");
            try
            {
                renderReady.Wait(); // wait for ke.render to finish Initialize()
                if (_cts.IsCancellationRequested) return;

                var factory = _resourceQueue.CreateFactory();
                _meshCache     = FrameworkBackends.Required.CreateResourceCache();
                _materialCache = FrameworkBackends.Required.CreateResourceCache();
                _textureCache  = FrameworkBackends.Required.CreateResourceCache();
                Resources = new ResourceManager(factory, _meshCache, _materialCache, _textureCache);
                // Give Tree access to ResourceManager for resource properties in auto-registration.
                Tree.SetResourceManager(Resources);
                // Phase 5.3: expose to MeshRenderer.Start so Material colors authored as
                // [entity.properties] MaterialBaseColor can be resolved into a GPU handle.
                FrameworkBackends.Resources = Resources;
                var modelLoader = Services.GetService<IAssetLoader>();
                var imageLoader = Services.GetService<IImageLoader>();
                var fontLoader  = Services.GetService<IFontLoader>();
                // Asset resolver: maps res:// + absolute paths to typed CPU-side data via the
                // native ke_asset_resolver plugin. The backend factory handles the image-loader
                // pointer extraction internally — sugar layer never sees a ke_image_loader*.
                _assetResolver = FrameworkBackends.Required.CreateAssetResolver(imageLoader, AppContext.BaseDirectory);

                if (modelLoader != null || imageLoader != null || fontLoader != null)
                    Assets = new Assets(modelLoader, imageLoader, fontLoader, Resources, _textureCache, _assetResolver);

                // Scene tree — Framework's Tree implements ISceneTree directly (S7).
                _sceneTree = Tree;

                // Auto-load action bindings (when a game enum was registered via .AddInputActions<T>()).
                // After this, InputActions.Get<TEnum>() works from anywhere; no game code involved.
                Services.GetService<InputActions.IAutoLoader>()?.Load(this);

                // Cache Project's render defaults (applied each frame just before OnUpdate).
                LoadProjectRenderSettings();

                // If the project declares a default scene, load it before OnReady runs — the scene
                // is the starting state of the world; OnReady is the place to customize it further.
                LoadDefaultSceneIfDeclared();

                // Await so async setup (e.g. scene loading + async resource creation) completes
                // before the first sim tick. Without this, an async OnReady becomes fire-and-forget
                // and the frame loop races the lambda's continuation.
                if (OnReady != null) OnReady(factory).GetAwaiter().GetResult();
                Logger?.Info("Application", "ke.sim: ready — entering frame loop");
                simReady.Set(); // signal ke.render that OnReady is complete

                while (!_cts.IsCancellationRequested)
                {
                    Time.NewFrame();
                    var packet = frameSync.BeginWrite();
                    if (_cts.IsCancellationRequested) { packet.EndWrite(); break; } // poison-pill

                    var input = _inputBuffer.Consume();
                    var writer = new FramePacketSceneWriter(packet, _kernelFactory);

                    // InputContext.Current spans the whole frame's game-logic phase so Node.Update,
                    // LateUpdate, and OnInput handlers can read polling state directly. World.Update
                    // still sets/clears it again internally — defensive double-set is harmless.
                    InputContext.Set(input);
                    Physics2DContext.Set(Services.GetService<IPhysics2D>(), _physics2DSystem);
                    try
                    {
                        // Drain queued input events and dispatch through the tree before any update
                        // logic runs — node OnInput handlers can flip state that Update consumes.
                        var events = _eventBuffer.Drain();
                        if (events.Length > 0)
                            Tree.DispatchInput(events);

                        // Action layer: evaluate every registered map against the current snapshot.
                        _actionEventBuffer.Clear();
                        foreach (var map in InputActions.AllMaps)
                            map.Evaluate(input, _actionEventBuffer);
                        if (_actionEventBuffer.Count > 0)
                            Tree.DispatchInputActions(_actionEventBuffer);

                        // Node lifecycle, in tree pre-order. Ordering relative to ECS systems:
                        //   Awake+Start (one-shot) → Update → ECS systems → LateUpdate
                        // Game logic that needs ECS-post-Transform reads (e.g. camera follow) goes
                        // in LateUpdate; the kernel ScriptSystem is no longer the script driver.
                        var dt = Time.DeltaTime;
                        Tree.TickAwakeAndStart();
                        Tree.TickUpdate(dt);

                        ActiveWorld?.Update(packet: packet, input: input);

                        Tree.TickLateUpdate(dt);

                        // Project-level render defaults (clear color + ambient). Applied every frame
                        // because FramePacket carries them per-frame. Game's OnUpdate can override.
                        if (_projectClearColor is { } cc) writer.ClearColor(cc.X, cc.Y, cc.Z, cc.W);
                        if (_projectAmbientLight is { } al) writer.SetAmbientLight(al.X, al.Y, al.Z);

                        OnUpdate?.Invoke(writer, input);
                    }
                    finally
                    {
                        InputContext.Set(null);
                        Physics2DContext.Set(null, null);
                    }

                    packet.EndWrite();
                }
            }
            catch (Exception ex)
            {
                simException = ex;
                Logger?.Error("Application", $"ke.sim fatal exception: {ex.Message}");
                _cts.Cancel();
            }
            finally
            {
                // Signal ke.render to exit BeginRead if it's waiting (poison pill)
                try { var p = frameSync.BeginWrite(); p.EndWrite(); } catch { }
            }
        }) { Name = "ke.sim", IsBackground = false };
        simThread.Start();

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
                {
                    int n = Input.DrainEvents(_eventStaging);
                    if (n > 0) _eventBuffer.Enqueue(_eventStaging.AsSpan(0, n));
                    _inputBuffer.Produce(Input.CaptureSnapshot());
                }

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

    // ── Project [render] section ──────────────────────────────────────────────

    private void LoadProjectRenderSettings()
    {
        var config = Services.GetService<KernelEngine.Configuration.IProjectConfig>();
        if (config is null || !config.IsLoaded) return;

        var render = config.GetSection("render");
        if (render is null) return;

        if (render.TryGetValue("clear_color", out var ccRaw) && ccRaw is Tomlyn.Model.TomlArray cc && cc.Count == 4)
            _projectClearColor = new System.Numerics.Vector4(ToF(cc[0]), ToF(cc[1]), ToF(cc[2]), ToF(cc[3]));

        if (render.TryGetValue("ambient_light", out var alRaw) && alRaw is Tomlyn.Model.TomlArray al && al.Count == 3)
            _projectAmbientLight = new System.Numerics.Vector3(ToF(al[0]), ToF(al[1]), ToF(al[2]));

        static float ToF(object? v) => v switch
        {
            long l => l,
            double d => (float)d,
            float f => f,
            int n => n,
            _ => System.Convert.ToSingle(v, System.Globalization.CultureInfo.InvariantCulture),
        };
    }

    // ── Default scene auto-load ───────────────────────────────────────────────

    private void LoadDefaultSceneIfDeclared()
    {
        var config = Services.GetService<KernelEngine.Configuration.IProjectConfig>();
        if (config is null || !config.IsLoaded) return;

        var project = config.GetSection("project");
        if (project is null || !project.TryGetValue("default_scene", out var raw)) return;
        if (raw is not string resPath) return;

        const string prefix = "res://";
        if (!resPath.StartsWith(prefix, StringComparison.Ordinal))
            throw new InvalidDataException($"[project] default_scene must start with 'res://'; got '{resPath}'");

        var relative = resPath[prefix.Length..];
        var absolute = Path.Combine(AppContext.BaseDirectory, relative);
        SceneLoader.LoadAsync(Tree, absolute, Resources, Services).GetAwaiter().GetResult();
        Logger?.Info("Application", $"Loaded default scene: {resPath}");
    }

    // ── Systems setup ─────────────────────────────────────────────────────────

    private void InitializeSystems()
    {
        // IDs are owned by the world (not static), so creating a second world doesn't clobber the first.
        var dirLightCid   = ActiveWorld.GetOrRegisterComponentId<LightComponent>("LightComponent");
        var pointLightCid = ActiveWorld.GetOrRegisterComponentId<PointLightComponent>("PointLightComponent");
        var spotLightCid  = ActiveWorld.GetOrRegisterComponentId<SpotLightComponent>("SpotLightComponent");
        var cameraCid     = ActiveWorld.GetOrRegisterComponentId<CameraComponent>("CameraComponent");
        var meshCid       = ActiveWorld.GetOrRegisterComponentId<MeshComponent>("ke_mesh_renderer");
        var skyboxCid     = ActiveWorld.GetOrRegisterComponentId<SkyboxComponent>("Skybox");

        MeshRenderer.DefaultMeshHandle     = new(0);
        MeshRenderer.DefaultMaterialHandle = new(0);

        var xformCid = ActiveWorld.TransformComponentId;

        // All render systems are pure-managed now — render/core C++ is no longer in the pipeline.
        ActiveWorld.AddSystem(new CameraRenderSystem(cameraCid, xformCid));
        ActiveWorld.AddSystem(new LightRenderSystem(dirLightCid, pointLightCid, spotLightCid, xformCid));
        ActiveWorld.AddSystem(new MeshRenderSystem(meshCid, xformCid));
        ActiveWorld.AddSystem(new SkyboxRenderSystem(skyboxCid));
        // Label rendering — polls current backbuffer size each frame so resizes propagate.
        ActiveWorld.AddSystem(new LabelRenderSystem(() =>
        {
            var sz = Window.GetSize();
            return sz.IsOk ? ((uint)sz.Value.Width, (uint)sz.Value.Height) : (0u, 0u);
        }));

        _shadowSystem = new ShadowRenderSystem(dirLightCid, meshCid, xformCid);
        ActiveWorld.AddSystem(_shadowSystem);

        // Physics 2D: auto-register when a backend is in DI (chapter 24 §5 "Physics2DSystem auto-registered").
        // Game code never instantiates this and never calls IPhysics2D.Step.
        var physics2D = Services.GetService<IPhysics2D>();
        if (physics2D != null)
        {
            _physics2DSystem = new Physics2DSystem(physics2D);
            ActiveWorld.AddSystem(_physics2DSystem);
        }
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
        // Destroy all nodes via ISceneTree (Tree implements it directly — S7).
        if (_sceneTree != null)
            _sceneTree.DestroyAll();
        else
            _scene?.DestroyAll();
        ActiveWorld?.Dispose();
        _meshCache?.Dispose();
        _materialCache?.Dispose();
        _textureCache?.Dispose();

        _proxyAllocator?.Report(Logger);

        (Services as IDisposable)?.Dispose();
        _proxyAllocator?.Dispose();
    }
}
