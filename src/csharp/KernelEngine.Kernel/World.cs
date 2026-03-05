using System.Diagnostics;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// The simulation world — owns the ECS registry, drives per-frame systems, and
/// exposes the scene-graph facade.
/// </summary>
public sealed unsafe class World : IDisposable
{
    private ke_world* _native;
    private Scene? _scene;
    private EcsRegistry? _registry;
    private readonly List<ISystem> _systems = [];

    internal ke_world* Native
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

    /// <summary>Creates a world bound to the given renderer and window.</summary>
    public World(Allocator allocator, Renderer renderer, Window window)
    {
        var desc = new ke_world_descriptor
        {
            allocator = allocator.Native,
            renderer = renderer.Native,
            window = window.Native,
        };
        ke_world* world;
        KernelException.ThrowIfFailed(NativeMethods.world_create(&desc, &world));
        _native = world;

        TransformComponentId = _native->transform_id(_native);
        HierarchyComponentId = _native->hierarchy_id(_native);
        NameComponentId      = _native->name_id(_native);
        ScriptComponentId    = _native->script_id(_native);
    }

    // ── Public properties ─────────────────────────────────────────────────────

    /// <summary>The scene facade for this world.</summary>
    public Scene Scene => _scene ??= new Scene(this);

    /// <summary>The ECS registry for this world.</summary>
    public EcsRegistry Registry => _registry ??= new EcsRegistry(_native->get_registry(_native));

    /// <summary>Entity ID of the active camera. <see cref="CameraRenderSystem"/> reads this each frame.</summary>
    public ulong ActiveCamera { get; set; }

    // ── Systems ───────────────────────────────────────────────────────────────

    /// <summary>Registers a managed system to be called each frame after the built-in C systems.</summary>
    public void AddSystem(ISystem system) => _systems.Add(system);

    // ── Update ────────────────────────────────────────────────────────────────

    /// <summary>
    /// Advances the simulation by one frame.
    /// Runs the C ScriptSystem + TransformSystem, then all registered <see cref="ISystem"/>s.
    /// </summary>
    public Result Update()
    {
        var now = _stopwatch.Elapsed;
        var dt = (float)(now - _lastTime).TotalSeconds;
        _lastTime = now;

        var frame = new ke_frame { delta_time = dt };
        var res = Native->update(Native, &frame);
        if (res != ke_result.KE_OK) return res;

        foreach (var system in _systems)
            system.Update(this, dt);

        return ke_result.KE_OK;
    }

    // ── Internal helpers used by Scene ────────────────────────────────────────

    internal ulong GetRoot() => Native->get_root(Native);

    internal ulong CreateNode(string name, ulong parent)
    {
        var namePtr = Marshal.StringToHGlobalAnsi(name);
        try { return Native->create_node(Native, (sbyte*)namePtr, parent); }
        finally { Marshal.FreeHGlobal(namePtr); }
    }

    internal Result DestroyNode(ulong entity) => Native->destroy_node(Native, entity);

    // ── Disposal ──────────────────────────────────────────────────────────────

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
            _scene = null;
            _registry = null;
        }
    }
}
