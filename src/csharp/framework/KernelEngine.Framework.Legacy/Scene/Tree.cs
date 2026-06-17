using System.Numerics;
using System.Runtime.InteropServices;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Tree graph facade built on top of the ECS world.
/// Manages a hierarchy of <see cref="Node"/> instances backed by ECS entities.
/// Node/Tree are framework-level concepts; the ECS world itself knows only
/// entities, components, and systems.
/// </summary>
public sealed class Tree : ISceneTree, IDisposable
{
    private readonly IWorld              _world;
    private readonly Node                _root;
    private readonly IServiceProvider?   _services;
    private ResourceManager?             _resources; // set after ResourceManager is created
    private readonly ISceneTreeBackend   _native;

    /// <summary>
    /// Constructs a Tree on top of <paramref name="world"/> using the supplied scene-tree
    /// backend. Backend creation lives in <c>KernelEngine.Framework.Legacy.Native</c> — this
    /// sugar layer accepts the interface so callers (or tests) can swap impls without
    /// touching kernel pointers.
    /// </summary>
    public Tree(IWorld world,
                ISceneTreeBackend  backend,
                IServiceProvider?  services         = null)
    {
        _world            = world;
        _services         = services;
        _native           = backend;
        var rootEntity    = _native.Root;
        AttachTransform(rootEntity);
        _root             = new Node(rootEntity, world, "Root");
    }

    /// <summary>
    /// Convenience constructor that resolves the scene-tree backend from
    /// <paramref name="backendFactory"/> at construction time.
    /// </summary>
    public Tree(IWorld world,
                IFrameworkBackendFactory backendFactory,
                IServiceProvider?        services         = null)
        : this(world, backendFactory.CreateSceneTree(world), services) { }

    /// <summary>
    /// Convenience constructor that pulls the scene-tree backend from the process-wide
    /// <see cref="FrameworkBackends.Required"/>. Throws if no backend was registered.
    /// </summary>
    public Tree(IWorld world,
                IServiceProvider?  services         = null)
        : this(world, FrameworkBackends.Required, services) { }

    // Holds scene loaders that have written scene_properties components into the
    // world — their per-loader arena owns the component's variant entry storage,
    // so the loader must outlive every entity that holds a scene_properties
    // component. Disposed alongside the tree.
    internal readonly List<ISceneLoaderBackend> _retainedLoaders = new();

    public void Dispose()
    {
        foreach (var l in _retainedLoaders) l.Dispose();
        _retainedLoaders.Clear();
        _native.Dispose();
    }

    internal ISceneTreeBackend  NativeWrapper    => _native;
    internal IWorld             World            => _world;

    private void AttachTransform(ulong entity)
    {
        var reg = _world.Registry;
        if (reg.GetComponent<TransformComponent>(entity, _world.TransformComponentId).IsEmpty)
        {
            var t = reg.AddComponent<TransformComponent>(entity, _world.TransformComponentId);
            t[0] = new TransformComponent
            {
                Position    = Vector3.Zero,
                Rotation    = Quaternion.Identity,
                Scale       = Vector3.One,
                WorldMatrix = Matrix4x4.Identity,
            };
        }
    }

    /// <summary>
    /// Provides the <see cref="ResourceManager"/> for auto-registration of types that have
    /// resource properties (<c>res://</c>). Set by Application after ResourceManager is created.
    /// </summary>
    internal void SetResourceManager(ResourceManager resources) => _resources = resources;

    private const ulong KE_ENTITY_INVALID = 0;

    /// <summary>The implicit root node of this Tree.</summary>
    public Node Root => _root;

    /// <summary>
    /// Locates a node. Accepts three forms:
    /// <list type="bullet">
    ///   <item><c>"Name"</c> — pre-order recursive search by name from the root (first match wins).</item>
    ///   <item><c>"/Path"</c> or <c>"/Path/Subpath"</c> — absolute path from the root, segment by segment.</item>
    ///   <item><c>"./relative"</c> — same as the absolute form (the leading <c>"."</c> is just hygiene).</item>
    /// </list>
    /// Returns <c>null</c> when not found. Case-sensitive.
    /// </summary>
    public Node? FindNode(string nameOrPath)
    {
        if (string.IsNullOrEmpty(nameOrPath)) return null;
        ulong entity = _native.FindNode(nameOrPath);
        return entity == KE_ENTITY_INVALID ? null : Node.FromEntity(entity);
    }

    /// <summary>Typed convenience over <see cref="FindNode(string)"/>.</summary>
    public T? FindNode<T>(string nameOrPath) where T : Node => FindNode(nameOrPath) as T;

    /// <summary>
    /// The <see cref="Camera"/> currently rendering the tree, or <c>null</c> if none is active.
    /// A <see cref="Camera"/> auto-activates when added and no other is current; switch with
    /// <see cref="Camera.MakeCurrent"/>.
    /// </summary>
    public Camera? CurrentCamera
    {
        get
        {
            var entity = _world.ActiveCamera;
            return entity == 0 ? null : Node.FromEntity(entity) as Camera;
        }
    }

    // ── High-level add ────────────────────────────────────────────────────────

    /// <summary>
    /// Creates a plain (non-scripted) node as a child of <paramref name="parent"/>
    /// (defaults to <see cref="Root"/>).
    /// </summary>
    public Node AddNode(string name, Node? parent = null)
    {
        var parentNode = parent ?? _root;
        var uniqueName = MakeUniqueChildName(parentNode, name);
        var entity = _native.CreateNode(uniqueName, parentNode.Entity);
        return new Node(entity, _world, uniqueName);
    }

    /// <summary>
    /// Adds <paramref name="node"/> as a child of <paramref name="parent"/> (defaults to <see cref="Root"/>).
    /// <para>
    /// When <paramref name="name"/> is omitted, the node's own <see cref="Node.Name"/> is used
    /// (which defaults to the type's short name — Godot-like). When the chosen name collides with
    /// an existing sibling, the engine auto-suffixes (<c>"Paddle"</c>, <c>"Paddle_2"</c>, <c>"Paddle_3"</c>).
    /// </para>
    /// <para>
    /// Lifecycle (<see cref="Node.Awake"/> / <see cref="Node.Start"/> / <see cref="Node.Update"/> /
    /// <see cref="Node.LateUpdate"/>) is driven by the tree-walking dispatcher (see <see cref="TickUpdate"/>).
    /// </para>
    /// </summary>
    public T AddNode<T>(T node, string? name = null, Node? parent = null) where T : Node
    {
        var parentNode = parent ?? _root;
        var requested  = name ?? node.Name;
        var uniqueName = MakeUniqueChildName(parentNode, requested);
        var entity = _native.CreateNode(uniqueName, parentNode.Entity);
        node.Initialize(entity, _world, uniqueName);
        // Phase 5.6: the auto-register-T-against-the-node-type-registry block
        // is gone with the registry itself; scenes now use [entity.script] and
        // resolve types via NodeTypeResolver on demand.
        return node;
    }

    /// <summary>
    /// Wraps an existing ECS entity (already created by the SceneLoader from a
    /// component-driven <c>[[entity]]</c> file) with a C# <typeparamref name="T"/>
    /// instance. Use this when migrating game code from the legacy
    /// <c>[[node]] type="Paddle"</c> path — the loader creates entities and
    /// writes their component fields, then the game asks the tree to materialise
    /// a typed wrapper for the entities it wants to interact with from C#.
    /// </summary>
    /// <remarks>
    /// Per the ECS-pure-nodes refactor's open decision #1, wrapping is explicit:
    /// the loader doesn't auto-create C# instances for every entity, only data
    /// is written into components. Game code calls WrapEntity for each entity
    /// it wants Update/OnInput hooks on.
    ///
    /// The wrapper's <see cref="Node.Name"/> is read from the entity's name
    /// component (set by the scene tree at create_node time). Returns the same
    /// wrapper on repeated calls for the same entity — wrappers are 1:1 with
    /// entities and live in Node's static registry.
    /// </remarks>
    public T WrapEntity<T>(ulong entity) where T : Node, new()
        => WrapEntity(new T(), entity);

    /// <summary>
    /// Same as <see cref="WrapEntity{T}(ulong)"/> but takes a pre-constructed instance,
    /// so callers can use DI (<see cref="ActivatorUtilities"/>) to inject constructor
    /// dependencies that the parameterless overload cannot supply.
    /// </summary>
    public T WrapEntity<T>(T node, ulong entity) where T : Node
    {
        if (entity == KE_ENTITY_INVALID)
            throw new ArgumentException("Cannot wrap KE_ENTITY_INVALID.", nameof(entity));
        ArgumentNullException.ThrowIfNull(node);

        // Idempotent: re-wrapping the same entity returns the existing instance
        // when its concrete type matches.
        if (Node.FromEntity(entity) is T existing) return existing;

        // The entity already has a Name component (added by scene_tree.create_node);
        // reuse it so paths keep resolving against the scene file's chosen names.
        var nameComp = _world.Registry.GetComponent<NameComponent>(entity, _world.NameComponentId);
        var nameStr  = nameComp.IsEmpty ? typeof(T).Name : ReadName(ref nameComp[0]);

        node.Initialize(entity, _world, nameStr);
        return node;
    }

    private static string ReadName(ref NameComponent c)
    {
        // InlineArray(64): read as Span<byte>, slice to the NUL terminator,
        // decode as UTF-8. No unsafe — the Framework project enforces it.
        var span = ((Span<byte>)c.Name);
        int len = span.IndexOf((byte)0);
        if (len < 0) len = span.Length;
        return System.Text.Encoding.UTF8.GetString(span[..len]);
    }

    private static string MakeUniqueChildName(Node parent, string requested)
    {
        if (!HasChildNamed(parent, requested)) return requested;
        for (int i = 2; ; i++)
        {
            var candidate = $"{requested}_{i}";
            if (!HasChildNamed(parent, candidate)) return candidate;
        }
    }

    private static bool HasChildNamed(Node parent, string name)
    {
        for (var c = parent.FirstChild; c != null; c = c.NextSibling)
            if (c.Name == name) return true;
        return false;
    }

    // ── Input dispatch ────────────────────────────────────────────────────────

    /// <summary>
    /// Dispatches a batch of input events to every node, in pre-order from <see cref="Root"/>.
    /// Stops visiting further nodes for an event as soon as a handler calls <c>evt.Consume()</c>;
    /// the next event in the batch restarts at the root.
    /// </summary>
    public void DispatchInput(InputEvent[] events)
    {
        if (events is null || events.Length == 0) return;
        for (int i = 0; i < events.Length; i++)
        {
            ref var evt = ref events[i];
            DispatchInputRecursive(_root, ref evt);
        }
    }

    private static void DispatchInputRecursive(Node node, ref InputEvent evt)
    {
        node.TickInput(ref evt);
        if (evt.Handled) return;
        for (var c = node.FirstChild; c != null; c = c.NextSibling)
        {
            DispatchInputRecursive(c, ref evt);
            if (evt.Handled) return;
        }
    }

    /// <summary>
    /// Dispatches a batch of action events to every node, in pre-order from <see cref="Root"/>.
    /// Same propagation rules as <see cref="DispatchInput"/>: <c>evt.Consume()</c> stops the rest
    /// of the tree from seeing this event; the next event in the batch restarts at the root.
    /// </summary>
    public void DispatchInputActions(List<InputActionEvent> events)
    {
        if (events is null || events.Count == 0) return;
        for (int i = 0; i < events.Count; i++)
        {
            var evt = events[i];
            DispatchInputActionRecursive(_root, ref evt);
        }
    }

    private static void DispatchInputActionRecursive(Node node, ref InputActionEvent evt)
    {
        node.TickInputAction(ref evt);
        if (evt.Handled) return;
        for (var c = node.FirstChild; c != null; c = c.NextSibling)
        {
            DispatchInputActionRecursive(c, ref evt);
            if (evt.Handled) return;
        }
    }

    // ── Destruction ───────────────────────────────────────────────────────────

    /// <summary>
    /// Destroys a node (and all its descendants). Fires <see cref="Node.OnDestroy"/> in post-order
    /// (children before parents) — a child can still read its parent's state during teardown — then
    /// disposes any node implementing <see cref="IDisposable"/>, unregisters them from the managed
    /// registry, and frees their ECS entities. Do not use <paramref name="node"/> after this call.
    /// </summary>
    public void DestroyNode(Node node)
    {
        TickDestroyRecursive(node);
        UnregisterNodesRecursive(node);
        _native.DestroyNode(node.Entity);
    }

    private static void UnregisterNodesRecursive(Node node)
    {
        for (var c = node.FirstChild; c != null; c = c.NextSibling)
            UnregisterNodesRecursive(c);
        Node.Unregister(node.Entity);
    }

    /// <summary>
    /// Engine-internal: drives <see cref="Node.OnDestroy"/> on every live node post-order from
    /// the root. Called by <see cref="Application.Dispose"/> so app-shutdown also runs the hook
    /// (without freeing entities, since the world is going away anyway).
    /// </summary>
    internal void DestroyAll()
    {
        TickDestroyRecursive(_root);
    }

    private static void TickDestroyRecursive(Node node)
    {
        for (var c = node.FirstChild; c != null; c = c.NextSibling)
            TickDestroyRecursive(c);
        node.TickDestroy();
    }

    // ── Lifecycle dispatch ────────────────────────────────────────────────────
    //   Pre-order walk: parent before children, siblings left-to-right.
    //   Application calls these once per sim frame, in order:
    //     TickAwakeAndStart → TickUpdate → TickLateUpdate

    internal void TickAwakeAndStart() => Walk(_root, static n => n.TickAwakeAndStart());

    internal void TickUpdate(float dt) => WalkDt(_root, dt, static (n, d) => n.TickUpdate(d));

    internal void TickLateUpdate(float dt) => WalkDt(_root, dt, static (n, d) => n.TickLateUpdate(d));

    private static void Walk(Node n, Action<Node> visit)
    {
        visit(n);
        for (var c = n.FirstChild; c != null; c = c.NextSibling) Walk(c, visit);
    }

    private static void WalkDt(Node n, float dt, Action<Node, float> visit)
    {
        visit(n, dt);
        for (var c = n.FirstChild; c != null; c = c.NextSibling) WalkDt(c, dt, visit);
    }

    // ── ISceneTree ────────────────────────────────────────────────────────────

    ulong ISceneTree.Root => _root.Entity;

    ulong ISceneTree.CreateNode(string name, ulong parentEntity) =>
        _native.CreateNode(name, parentEntity);

    bool ISceneTree.DestroyNode(ulong entity)
    {
        var node = Node.FromEntity(entity);
        if (node == null) return false;
        DestroyNode(node);
        return true;
    }

    void ISceneTree.DestroyAll() => DestroyAll();

    ulong ISceneTree.FindNode(string nameOrPath) =>
        FindNode(nameOrPath)?.Entity ?? 0UL;
}
