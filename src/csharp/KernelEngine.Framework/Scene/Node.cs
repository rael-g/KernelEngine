using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A Tree node backed by an ECS entity. Represents a spatial object with optional behavior.
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
    private string _name;

    /// <summary>Parameterless constructor for user subclasses. Default <see cref="Name"/> is the type's short name (Godot-like).</summary>
    protected Node()
    {
        _name = GetType().Name;
    }

    /// <summary>Internal constructor for wrapping an existing entity (e.g. root).</summary>
    internal Node(ulong entity, IWorld world, string name)
    {
        _entity = entity;
        _world = world;
        _name = name;
        s_registry[_entity] = this;
    }

    /// <summary>Called by <see cref="Tree.AddNode{T}"/> to bind this instance to an entity.</summary>
    internal void Initialize(ulong entity, IWorld world, string name)
    {
        _entity = entity;
        _world = world;
        _name = name;
        s_registry[_entity] = this;
    }

    // ── Identity ──────────────────────────────────────────────────────────────

    /// <summary>The ECS entity ID. Engine-internal — game code interacts with nodes, not entities.</summary>
    internal ulong Entity => _entity;

    /// <summary>The owning world. Engine-internal — exposed to built-in nodes (e.g. Camera) for live ECS access.</summary>
    internal IWorld? World => _world;

    /// <summary>
    /// Node name. Defaults to the type's short name (e.g. <c>"Paddle"</c> for <c>class Paddle : Node</c>).
    /// <see cref="Tree.AddNode{T}"/> auto-suffixes on collision under the same parent (<c>"Paddle"</c>,
    /// <c>"Paddle_2"</c>, ...). Settable post-construction; the ECS name component is not currently
    /// updated on rename (the engine reads names by Tree walk, not via the component).
    /// </summary>
    public string Name
    {
        get => _name;
        set => _name = value ?? throw new ArgumentNullException(nameof(value));
    }

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

    // ── Path-based navigation (Godot-like) ─────────────────────────────────────

    /// <summary>
    /// Resolves a node relative to this one. Path is slash-separated:
    /// <list type="bullet">
    ///   <item><c>"."</c> → self.</item>
    ///   <item><c>".."</c> → parent.</item>
    ///   <item><c>"Child"</c> → direct child named <c>Child</c>.</item>
    ///   <item><c>"Child/Grandchild"</c> → walks down.</item>
    ///   <item><c>"../Sibling"</c> → goes up then down.</item>
    /// </list>
    /// Returns <c>null</c> if any segment is missing. Path is leading/trailing-slash tolerant.
    /// </summary>
    public Node? GetNode(string path)
    {
        if (string.IsNullOrEmpty(path) || path == ".") return this;

        Node? current = this;
        foreach (var seg in path.Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            if (current is null) return null;
            current = seg == ".." ? current.Parent : current.FindChild(seg);
        }
        return current;
    }

    /// <summary>Typed convenience over <see cref="GetNode"/>.</summary>
    public T? GetNode<T>(string path) where T : Node => GetNode(path) as T;

    private Node? FindChild(string name)
    {
        for (var c = FirstChild; c != null; c = c.NextSibling)
            if (c.Name == name) return c;
        return null;
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
    //   Override virtuals in subclasses; instances can additionally hook the On* actions
    //   (no override needed). Both fire each tick: virtual first, then action.
    //
    //   Per-frame order (driven by Tree walks from ke.sim):
    //     1. Awake + Start  — one-shot on the first tick after the node is added
    //     2. Update         — every frame
    //     3. LateUpdate     — every frame, after Update of every node
    //
    //   Tree-walk order within each pass is pre-order (parent before children, siblings
    //   left-to-right). Game code can rely on it.

    private bool _started;

    /// <summary>Called once when the node enters the tree, before <see cref="Start"/>.</summary>
    protected virtual void Awake() { }

    /// <summary>Called once before the first <see cref="Update"/> call. Override to initialize.</summary>
    protected virtual void Start() { }

    /// <summary>Called every sim frame. Override to drive per-frame behavior.</summary>
    protected virtual void Update(float deltaTime) { }

    /// <summary>Called every sim frame, after <see cref="Update"/> of every node.</summary>
    protected virtual void LateUpdate(float deltaTime) { }

    /// <summary>
    /// Called once per input event each sim frame, in tree pre-order (parent then children).
    /// Override to react to discrete events; call <c>evt.Consume()</c> to stop propagation.
    /// </summary>
    protected virtual void OnInput(ref InputEvent evt) { }

    /// <summary>Instance hook fired after <see cref="Awake"/>.</summary>
    public Action? OnAwakeEvent { get; set; }

    /// <summary>Instance hook fired after <see cref="Start"/>.</summary>
    public Action? OnStart { get; set; }

    /// <summary>Instance hook fired after <see cref="Update"/>.</summary>
    public Action<float>? OnUpdate { get; set; }

    /// <summary>Instance hook fired after <see cref="LateUpdate"/>.</summary>
    public Action<float>? OnLateUpdate { get; set; }

    /// <summary>Instance hook fired after <see cref="OnInput"/> for each event.</summary>
    public InputHandler? OnInputEvent { get; set; }

    internal void TickInput(ref InputEvent evt)
    {
        OnInput(ref evt);
        OnInputEvent?.Invoke(ref evt);
    }

    internal void TickAwakeAndStart()
    {
        if (_started) return;
        Awake();
        OnAwakeEvent?.Invoke();
        Start();
        OnStart?.Invoke();
        _started = true;
    }

    internal void TickUpdate(float dt)
    {
        Update(dt);
        OnUpdate?.Invoke(dt);
    }

    internal void TickLateUpdate(float dt)
    {
        LateUpdate(dt);
        OnLateUpdate?.Invoke(dt);
    }

    // ── Internal registry ─────────────────────────────────────────────────────

    internal static Node? FromEntity(ulong entity) => s_registry.GetValueOrDefault(entity);

    internal static void Unregister(ulong entity) => s_registry.Remove(entity);

    internal static void ClearRegistry() => s_registry.Clear();
}
