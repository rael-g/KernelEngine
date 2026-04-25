using System.Diagnostics;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// The ECS simulation world — owns the registry, drives built-in systems (ScriptSystem,
/// TransformSystem), and exposes the built-in component IDs.
/// </summary>
public sealed unsafe class World : IDisposable
{
    private ke_world* _native;
    private EcsRegistry? _registry;
    private readonly List<ISystem> _systems = [];

    public ke_world* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    private readonly Stopwatch _stopwatch = Stopwatch.StartNew();
    private TimeSpan _lastTime;

    // ── Built-in component IDs (stable after construction) ────────────────────

    /// <summary>Component ID for <see cref="TransformComponent"/>.</summary>
    public uint TransformComponentId { get; private set; }

    /// <summary>Component ID for <see cref="HierarchyComponent"/>.</summary>
    public uint HierarchyComponentId { get; private set; }

    /// <summary>Component ID for the name component.</summary>
    public uint NameComponentId { get; private set; }

    /// <summary>Component ID for <see cref="ScriptComponent"/>.</summary>
    public uint ScriptComponentId { get; private set; }

    // ── Construction ──────────────────────────────────────────────────────────

    /// <summary>Creates a world bound to the given allocator.</summary>
    public World(Allocator allocator)
    {
        var parameters = new ke_world_params
        {
            allocator = allocator.Native,
        };
        ke_world* world;
        KernelException.ThrowIfFailed(NativeMethods.world_create(&parameters, &world));
        _native = world;

        TransformComponentId = _native->transform_id(_native);
        HierarchyComponentId = _native->hierarchy_id(_native);
        NameComponentId      = _native->name_id(_native);
        ScriptComponentId    = _native->script_id(_native);
    }

    // ── Public properties ─────────────────────────────────────────────────────

    /// <summary>The ECS registry for this world.</summary>
    public EcsRegistry Registry => _registry ??= new EcsRegistry(_native->get_registry(_native));

    private Scene? _scene;

    /// <summary>The scene graph facade for this world.</summary>
    public Scene Scene => _scene ??= new Scene(this);

    /// <summary>Entity ID of the active camera. <see cref="CameraRenderSystem"/> reads this each frame.</summary>
    public ulong ActiveCamera { get; set; }

    // ── Systems ───────────────────────────────────────────────────────────────

    private readonly SystemScheduler _scheduler = new();
    private bool _schedulerDirty = true;
    private TaskScheduler? _taskScheduler;

    public void AddSystem(ISystem system)
    {
        _systems.Add(system);
        _schedulerDirty = true;
    }

    /// <summary>Registers a native system descriptor into the world.</summary>
    public void AddSystem(ke_system_desc desc)
    {
        KernelException.ThrowIfFailed(_native->add_system(_native, &desc), "add_system");
    }

    /// <summary>
    /// Advances the simulation by one frame.
    /// Runs the C ScriptSystem + TransformSystem, then all registered <see cref="ISystem"/>s in parallel waves.
    /// </summary>
    public Result Update(FramePacket? packet = null)
    {
        var now = _stopwatch.Elapsed;
        var dt = (float)(now - _lastTime).TotalSeconds;
        _lastTime = now;

        var frame = new ke_frame { delta_time = dt };
        var res = Native->update(Native, &frame);
        if (res != ke_result.KE_OK) return res;

        // Lazily wrap the native task scheduler (null if none is configured — RunAsync falls back to sequential).
        if (_taskScheduler == null)
        {
            var nativeSched = _native->get_task_scheduler(_native);
            if (nativeSched != null)
                _taskScheduler = new TaskScheduler(nativeSched);
        }

        if (_schedulerDirty)
        {
            _scheduler.Build(_systems);
            _schedulerDirty = false;
        }

        // Run systems in waves (Sim thread waits for parallel workers to finish wave by wave)
        _scheduler.RunAsync(this, dt, packet, _taskScheduler!).GetAwaiter().GetResult();

        return ke_result.KE_OK;
    }

    // ── Disposal ──────────────────────────────────────────────────────────────

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
            _registry = null;
        }
    }
}
