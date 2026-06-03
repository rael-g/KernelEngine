using System.Numerics;
using System.Runtime.InteropServices;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Tree graph facade built on top of the ECS world.
/// Manages a hierarchy of <see cref="Node"/> instances backed by ECS entities.
/// Node/Tree are framework-level concepts; the ECS world itself knows only
/// entities, components, and systems.
/// </summary>
public sealed unsafe class Tree : ISceneTree, IDisposable
{
    private readonly IWorld              _world;
    private readonly Node                _root;
    private readonly INodeTypeRegistry?  _nodeTypeRegistry;
    private readonly IServiceProvider?   _services;
    private ResourceManager?             _resources; // set after ResourceManager is created
    private readonly ISceneTreeBackend   _native;

    private readonly HashSet<Type> _registeredTypes = [];

    public Tree(IWorld world,
                INodeTypeRegistry? nodeTypeRegistry = null,
                IServiceProvider?  services         = null)
    {
        _world            = world;
        _nodeTypeRegistry = nodeTypeRegistry;
        _services         = services;
        // The native scene tree owns the root entity (creates it with Hierarchy+Name
        // components). C# Tree only adds Transform on top, then wraps in a Node.
        var worldNative   = ((World)world).Native;
        _native           = new NativeSceneTree(worldNative, new MallocAllocator());
        var rootEntity    = _native.Root;
        AttachTransform(rootEntity);
        _root             = new Node(rootEntity, world, "Root");
    }

    public void Dispose() => _native.Dispose();

    internal ISceneTreeBackend  NativeWrapper    => _native;
    internal IWorld             World            => _world;
    internal INodeTypeRegistry? NodeTypeRegistry => _nodeTypeRegistry;

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
        var entity = CreateEntityWithHierarchy(uniqueName, parentNode.Entity);
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
        var entity     = CreateEntityWithHierarchy(uniqueName, parentNode.Entity);
        node.Initialize(entity, _world, uniqueName);

        // Auto-register the type so scene files can reference it by name without
        // explicit registration. First time only — subsequent adds of the same type are free.
        if (_nodeTypeRegistry != null && _registeredTypes.Add(typeof(T)))
            _nodeTypeRegistry.Register<T>(_world, _services, _resources);

        return node;
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

    // ── Entity/hierarchy management ───────────────────────────────────────────

    /// <summary>
    /// Creates an ECS entity initialised with Transform, Hierarchy, and Name components,
    /// and links it into the parent's child list.
    /// </summary>
    private ulong CreateEntityWithHierarchy(string name, ulong parent)
    {
        var reg    = _world.Registry;
        var entity = reg.CreateEntity();

        // Transform — default: origin, identity rotation, unit scale
        var t = reg.AddComponent<TransformComponent>(entity, _world.TransformComponentId);
        t[0] = new TransformComponent
        {
            Position    = Vector3.Zero,
            Rotation    = Quaternion.Identity,
            Scale       = Vector3.One,
            WorldMatrix = Matrix4x4.Identity,
        };

        // Hierarchy — link to parent, no children yet
        var h = reg.AddComponent<HierarchyComponent>(entity, _world.HierarchyComponentId);
        h[0] = new HierarchyComponent { Parent = parent };

        // Name
        var n = reg.AddComponent<NameComponent>(entity, _world.NameComponentId);
        SetName(ref n[0], name);

        // Prepend entity into parent's child list (O(1) doubly-linked prepend)
        if (parent != KE_ENTITY_INVALID)
        {
            var ph = reg.GetComponent<HierarchyComponent>(parent, _world.HierarchyComponentId);
            if (!ph.IsEmpty)
            {
                h[0].NextSibling = ph[0].FirstChild;
                if (ph[0].FirstChild != KE_ENTITY_INVALID)
                {
                    var sib = reg.GetComponent<HierarchyComponent>(ph[0].FirstChild, _world.HierarchyComponentId);
                    if (!sib.IsEmpty) sib[0].PrevSibling = entity;
                }
                ph[0].FirstChild = entity;
            }
        }

        return entity;
    }

    private static void SetName(ref NameComponent comp, string name)
    {
        if (string.IsNullOrEmpty(name)) return;
        var bytes = System.Text.Encoding.UTF8.GetBytes(name);
        int len = Math.Min(bytes.Length, 63);
        for (int i = 0; i < len; i++) comp.Name[i] = bytes[i];
        comp.Name[len] = 0;
    }

    // ── ISceneTree ────────────────────────────────────────────────────────────

    ulong ISceneTree.Root => _root.Entity;

    ulong ISceneTree.CreateNode(string name, ulong parentEntity) =>
        CreateEntityWithHierarchy(name, parentEntity == 0 ? _root.Entity : parentEntity);

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
