using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node backed by an ECS entity. Represents a spatial object with optional behavior.
/// <para>
/// Subclass and override <see cref="OnStart"/>/<see cref="OnUpdate"/> to attach behavior.
/// The entity is created by the world; transform and hierarchy live in ECS components.
/// </para>
/// </summary>
public class Node
{
    // Entity → managed Node, used for hierarchy navigation (Parent/FirstChild/NextSibling).
    private static readonly Dictionary<ulong, Node> s_registry = [];

    private ulong _entity;
    private IWorld? _world;
    private string _name = "";

    /// <summary>Parameterless constructor for user subclasses.</summary>
    protected Node() { }

    /// <summary>Internal constructor for wrapping an existing entity (e.g. root).</summary>
    internal Node(ulong entity, IWorld world, string name)
    {
        _entity = entity;
        _world = world;
        _name = name;
        s_registry[_entity] = this;
    }

    /// <summary>Called by <see cref="Scene.AddNode{T}"/> to bind this instance to an entity.</summary>
    internal void Initialize(ulong entity, IWorld world, string name)
    {
        _entity = entity;
        _world = world;
        _name = name;
        s_registry[_entity] = this;
    }

    /// <summary>
    /// Wires this node's <see cref="OnStart"/>/<see cref="OnUpdate"/> into the built-in C ScriptSystem
    /// via the world's managed registration API. No <c>unsafe</c> here — the function-pointer plumbing
    /// lives in the kernel concrete (<c>ScriptBridge</c>).
    /// </summary>
    internal void RegisterScript()
    {
        if (_world == null) return;
        s_registry[_entity] = this;
        _world.RegisterScript(_entity, TickStart, TickUpdate);
    }

    // ── Identity ──────────────────────────────────────────────────────────────

    /// <summary>The ECS entity ID. Immutable after node creation.</summary>
    public ulong Entity => _entity;

    /// <summary>The name given at node creation.</summary>
    public string Name => _name;

    // ── Transform ─────────────────────────────────────────────────────────────

    /// <summary>Local spatial transform (position, rotation, scale).</summary>
    public Transform LocalTransform
    {
        get
        {
            var slot = TransformSlot;
            if (slot.IsEmpty) return Transform.Identity;
            ref var c = ref slot[0];
            return new Transform { Position = c.Position, Rotation = c.Rotation, Scale = c.Scale };
        }
        set
        {
            var slot = TransformSlot;
            if (slot.IsEmpty) return;
            ref var c = ref slot[0];
            c.Position = value.Position;
            c.Rotation = value.Rotation;
            c.Scale = value.Scale;
        }
    }

    /// <summary>World-space matrix, computed each frame by the TransformSystem.</summary>
    public Matrix4x4 WorldMatrix
    {
        get
        {
            var slot = TransformSlot;
            return slot.IsEmpty ? Matrix4x4.Identity : slot[0].WorldMatrix;
        }
    }

    private Span<TransformComponent> TransformSlot =>
        _world == null
            ? Span<TransformComponent>.Empty
            : _world.Registry.GetComponent<TransformComponent>(_entity, _world.TransformComponentId);

    // ── Hierarchy ─────────────────────────────────────────────────────────────

    /// <summary>Parent node, or <c>null</c> if this is the root.</summary>
    public Node? Parent
    {
        get
        {
            var h = HierarchySlot;
            if (h.IsEmpty || h[0].Parent == 0) return null;
            return s_registry.GetValueOrDefault(h[0].Parent);
        }
    }

    /// <summary>First child, or <c>null</c> if none.</summary>
    public Node? FirstChild
    {
        get
        {
            var h = HierarchySlot;
            if (h.IsEmpty || h[0].FirstChild == 0) return null;
            return s_registry.GetValueOrDefault(h[0].FirstChild);
        }
    }

    /// <summary>Next sibling, or <c>null</c> if this is the last child.</summary>
    public Node? NextSibling
    {
        get
        {
            var h = HierarchySlot;
            if (h.IsEmpty || h[0].NextSibling == 0) return null;
            return s_registry.GetValueOrDefault(h[0].NextSibling);
        }
    }

    private Span<HierarchyComponent> HierarchySlot =>
        _world == null
            ? Span<HierarchyComponent>.Empty
            : _world.Registry.GetComponent<HierarchyComponent>(_entity, _world.HierarchyComponentId);

    // ── ECS helpers (engine-internal — user code expresses behavior with managed fields, not
    //    by adding components; new capabilities arrive as new nodes + systems, per F.0b) ─────

    internal Span<T> AddComponent<T>(uint componentId) where T : unmanaged =>
        _world == null ? Span<T>.Empty : _world.Registry.AddComponent<T>(_entity, componentId);

    /// <summary>Returns an empty span until the node is bound to a world (e.g. during init setters).</summary>
    internal Span<T> GetComponent<T>(uint componentId) where T : unmanaged =>
        _world == null ? Span<T>.Empty : _world.Registry.GetComponent<T>(_entity, componentId);

    internal void RemoveComponent(uint componentId)
    {
        if (_world != null) _world.Registry.RemoveComponent(_entity, componentId);
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    //   Override the methods (Start/Update) in subclasses; instances can additionally hook
    //   the On* actions (no override needed). Both fire each tick: method first, then action.

    /// <summary>Called once before the first <see cref="Update"/> call. Override to initialize.</summary>
    protected virtual void Start() { }

    /// <summary>Called every sim frame. Override to drive per-frame behavior.</summary>
    protected virtual void Update(float deltaTime) { }

    /// <summary>Instance hook fired after <see cref="Start"/>.</summary>
    public Action? OnStart { get; set; }

    /// <summary>Instance hook fired after <see cref="Update"/>.</summary>
    public Action<float>? OnUpdate { get; set; }

    private void TickStart()
    {
        Start();
        OnStart?.Invoke();
    }

    private void TickUpdate(float dt)
    {
        Update(dt);
        OnUpdate?.Invoke(dt);
    }

    // ── Internal registry ─────────────────────────────────────────────────────

    internal static Node? FromEntity(ulong entity) => s_registry.GetValueOrDefault(entity);

    internal static void Unregister(ulong entity) => s_registry.Remove(entity);

    internal static void ClearRegistry() => s_registry.Clear();
}
