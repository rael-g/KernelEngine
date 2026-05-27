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
public sealed class Tree
{
    private readonly IWorld _world;
    private readonly Node   _root;

    public Tree(IWorld world)
    {
        _world = world;
        var rootEntity = CreateEntityWithHierarchy("Root", KE_ENTITY_INVALID);
        _root = new Node(rootEntity, world, "Root");
    }

    private const ulong KE_ENTITY_INVALID = 0;

    /// <summary>The implicit root node of this Tree.</summary>
    public Node Root => _root;

    /// <summary>
    /// Pre-order search for the first descendant whose <see cref="Node.Name"/> matches.
    /// Returns <c>null</c> when not found. Case-sensitive by default — game code expecting
    /// case-insensitive matches should normalize node names at creation.
    /// </summary>
    public Node? FindNode(string name)
    {
        return FindRecursive(_root, name);

        static Node? FindRecursive(Node node, string name)
        {
            for (var c = node.FirstChild; c != null; c = c.NextSibling)
            {
                if (c.Name == name) return c;
                var found = FindRecursive(c, name);
                if (found != null) return found;
            }
            return null;
        }
    }

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
        var parentEntity = parent?.Entity ?? _root.Entity;
        var entity = CreateEntityWithHierarchy(name, parentEntity);
        return new Node(entity, _world, name);
    }

    /// <summary>
    /// Creates a scripted node as a child of <paramref name="parent"/>
    /// (defaults to <see cref="Root"/>). <see cref="Node.OnStart"/> and
    /// <see cref="Node.Awake"/>, <see cref="Node.Start"/>, <see cref="Node.EarlyUpdate"/>,
    /// <see cref="Node.Update"/>, and <see cref="Node.LateUpdate"/> are driven by the
    /// tree-walking lifecycle dispatcher (see <see cref="TickUpdate"/>).
    /// </summary>
    public T AddNode<T>(T node, string name, Node? parent = null) where T : Node
    {
        var parentEntity = parent?.Entity ?? _root.Entity;
        var entity = CreateEntityWithHierarchy(name, parentEntity);
        node.Initialize(entity, _world, name);
        return node;
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

    // ── Destruction ───────────────────────────────────────────────────────────

    /// <summary>
    /// Destroys a node (and all its descendants) and removes it from the scripting registry.
    /// Do not use <paramref name="node"/> after this call.
    /// </summary>
    public void DestroyNode(Node node)
    {
        Node.Unregister(node.Entity);
        DestroyEntityRecursive(node.Entity);
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

    /// <summary>Recursively destroys an entity and all its descendants, unlinking from parent.</summary>
    private void DestroyEntityRecursive(ulong entity)
    {
        var reg = _world.Registry;
        var h   = reg.GetComponent<HierarchyComponent>(entity, _world.HierarchyComponentId);
        if (h.IsEmpty) return;

        // Destroy children first (depth-first)
        var child = h[0].FirstChild;
        while (child != KE_ENTITY_INVALID)
        {
            var ch   = reg.GetComponent<HierarchyComponent>(child, _world.HierarchyComponentId);
            var next = !ch.IsEmpty ? ch[0].NextSibling : KE_ENTITY_INVALID;
            DestroyEntityRecursive(child);
            child = next;
        }

        // Unlink from parent's child list
        if (h[0].Parent != KE_ENTITY_INVALID)
        {
            var ph = reg.GetComponent<HierarchyComponent>(h[0].Parent, _world.HierarchyComponentId);
            if (!ph.IsEmpty && ph[0].FirstChild == entity)
                ph[0].FirstChild = h[0].NextSibling;

            if (h[0].PrevSibling != KE_ENTITY_INVALID)
            {
                var ps = reg.GetComponent<HierarchyComponent>(h[0].PrevSibling, _world.HierarchyComponentId);
                if (!ps.IsEmpty) ps[0].NextSibling = h[0].NextSibling;
            }
            if (h[0].NextSibling != KE_ENTITY_INVALID)
            {
                var ns = reg.GetComponent<HierarchyComponent>(h[0].NextSibling, _world.HierarchyComponentId);
                if (!ns.IsEmpty) ns[0].PrevSibling = h[0].PrevSibling;
            }
        }

        reg.DestroyEntity(entity);
    }

    private static void SetName(ref NameComponent comp, string name)
    {
        if (string.IsNullOrEmpty(name)) return;
        var bytes = System.Text.Encoding.UTF8.GetBytes(name);
        int len = Math.Min(bytes.Length, 63);
        for (int i = 0; i < len; i++) comp.Name[i] = bytes[i];
        comp.Name[len] = 0;
    }
}
