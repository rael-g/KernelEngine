using System.Text;
using KernelEngine.Ecs;

namespace KernelEngine.Framework;

/// <summary>
/// Node-aware facade over <see cref="World"/>. Game code calls <see cref="AddNode{T}"/>
/// to spawn entities and attach components; every entity is created through the
/// native <see cref="SceneTree"/> so hierarchy and name are wired at the C level.
/// </summary>
public sealed class NodeWorld
{
    private readonly World              _world;
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;
    private readonly uint               _nameCid;

    private readonly List<Node>                  _behaviors = new();
    private readonly List<Node>                  _allNodes  = new();
    private readonly Dictionary<ulong, Node>     _byEntity  = new();

    internal IReadOnlyList<Node>  Behaviors => _behaviors;

    /// <summary>
    /// Every currently-bound node. A caller needing its own node type filters
    /// this with <c>OfType&lt;T&gt;()</c> — NodeWorld has no per-domain knowledge.
    /// </summary>
    public IReadOnlyList<Node> AllNodes => _allNodes;

    private nint _systemCtx;

    /// <summary>
    /// Scopes <see cref="AddNode{T}"/>/<see cref="DestroyNode"/> to a running
    /// system's context for the duration of the returned handle, so structural
    /// changes defer to the wave barrier. Restores the prior value on dispose.
    /// </summary>
    internal SystemCtxScope EnterSystem(nint ctx) => new(this, ctx);

    internal readonly ref struct SystemCtxScope
    {
        private readonly NodeWorld _world;
        private readonly nint      _previous;
        public SystemCtxScope(NodeWorld world, nint ctx)
        {
            _world      = world;
            _previous   = world._systemCtx;
            world._systemCtx = ctx;
        }
        public void Dispose() => _world._systemCtx = _previous;
    }

    internal void RegisterBehavior(Node node) => _behaviors.Add(node);

    private readonly uint _nativeTransformCid;
    private readonly uint _hierarchyCid;

    internal NodeWorld(World world, IEcsRegistry ecs, IComponentRegistry components)
    {
        _world      = world;
        _ecs        = ecs;
        _components = components;
        _nameCid            = ecs.RegisterComponent<NameComponent>("name");
        _nativeTransformCid = ecs.RegisterComponent<TransformComponent>("transform");
        _hierarchyCid       = ecs.RegisterComponent<HierarchyComponent>("hierarchy");
    }

    /// <summary>
    /// Registers a node in the world: creates a native entity via the scene tree,
    /// binds the node to it, and lets the subclass materialize its components.
    /// </summary>
    public T AddNode<T>(T node, string name = "", Node? parent = null) where T : Node
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a world.");
        if (parent is not null && parent.NodeWorld != this)
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = _world.SceneTree.CreateNode(name, parent?.Entity ?? 0, _systemCtx);
        node.BindToNodeWorld(this, entity);
        _allNodes.Add(node);
        _byEntity[entity] = node;
        return node;
    }

    /// <summary>
    /// First phase used by the scene loader: assigns entity + name + parent,
    /// but does NOT yet invoke the subclass's OnBind. The loader applies
    /// component data then calls <see cref="CompleteAddNode"/>.
    /// </summary>
    internal void PreAddNode(Node node, string name, Node? parent)
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a world.");
        if (parent is not null && parent.NodeWorld != this)
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = _world.SceneTree.CreateNode(name, parent?.Entity ?? 0, _systemCtx);
        node.PreBind(this, entity);
        _allNodes.Add(node);
        _byEntity[entity] = node;
    }

    internal void CompleteAddNode(Node node) => node.CompleteBind();

    /// <summary>Finds a node by its exact name or path, resolved through the native scene tree.</summary>
    public Node? Find(string name)
    {
        var entity = _world.SceneTree.FindNode(name);
        return entity != 0 && _byEntity.TryGetValue(entity, out var n) ? n : null;
    }

    /// <summary>Finds a node by name and casts it to <typeparamref name="T"/>.</summary>
    public T? Find<T>(string name) where T : Node
    {
        var node = Find(name);
        if (node is null) return null;
        if (node is not T typed)
            throw new InvalidOperationException(
                $"Node '{name}' is a {node.GetType().Name}, not {typeof(T).Name}.");
        return typed;
    }

    /// <summary>
    /// Removes <paramref name="node"/> from the world, destroys its native entity,
    /// and clears its binding. Idempotent on unbound nodes.
    /// </summary>
    public void DestroyNode(Node node)
    {
        if (!node.IsBound || node.NodeWorld != this) return;
        var kids = node.Children.ToArray();
        for (int i = 0; i < kids.Length; i++) DestroyNode(kids[i]);

        node.OnUnbind();

        if (node.HasBehavior) _behaviors.Remove(node);
        _allNodes.Remove(node);
        _byEntity.Remove(node.Entity);
        _world.SceneTree.DestroyNode(node.Entity, _systemCtx);
        node.UnbindFromNodeWorld();
    }

    /// <summary>
    /// Destroys every node currently in the world. Used by <see cref="SceneRouter"/>
    /// to flush a scene before loading the next one.
    /// </summary>
    public void Clear()
    {
        var roots = _allNodes.Where(n => n.Parent is null).ToArray();
        for (int i = 0; i < roots.Length; i++) DestroyNode(roots[i]);
    }

    /// <summary>
    /// Binds a managed Node to an entity that was already created by the native
    /// scene loader (name/hierarchy already live in the ECS), skips native entity
    /// creation, and calls OnBind normally.
    /// </summary>
    internal void BindNativeEntity(Node node, ulong entity)
    {
        node.BindToNodeWorld(this, entity);
        _allNodes.Add(node);
        _byEntity[entity] = node;
    }

    /// <summary>
    /// Reads <paramref name="entity"/>'s display name straight from <c>ke_name_component</c>
    /// — never cached, so a native rename is visible on the next read without any
    /// sync step. "" for an entity with no name (or none at all).
    /// </summary>
    internal string GetName(ulong entity)
    {
        var nsp = _ecs.GetComponent<NameComponent>(entity, _nameCid);
        if (nsp.IsEmpty) return "";
        ReadOnlySpan<byte> bytes = nsp[0].Name;
        var end = bytes.IndexOf((byte)0);
        return Encoding.UTF8.GetString(end >= 0 ? bytes[..end] : bytes);
    }

    /// <summary>
    /// Resolves <paramref name="entity"/>'s parent node straight from
    /// <c>ke_hierarchy_component</c>. Null when the entity has no parent, or when
    /// the parent entity has no managed <see cref="Node"/> bound to it.
    /// </summary>
    internal Node? GetParent(ulong entity)
    {
        var hsp = _ecs.GetComponent<HierarchyComponent>(entity, _hierarchyCid);
        if (hsp.IsEmpty) return null;
        var parent = hsp[0].Parent;
        if (parent == 0) return null;
        return _byEntity.TryGetValue(parent, out var p) ? p : null;
    }

    /// <summary>
    /// Walks <paramref name="entity"/>'s child chain straight from
    /// <c>ke_hierarchy_component</c> (insertion order — see the scene tree's
    /// append-based linking). Skips any child with no managed <see cref="Node"/>
    /// bound to it, same as the old AttachChild-built list only ever held nodes.
    /// </summary>
    internal IReadOnlyList<Node> GetChildren(ulong entity)
    {
        var result = new List<Node>();
        var hsp = _ecs.GetComponent<HierarchyComponent>(entity, _hierarchyCid);
        if (hsp.IsEmpty) return result;

        var child = hsp[0].FirstChild;
        while (child != 0)
        {
            if (_byEntity.TryGetValue(child, out var node)) result.Add(node);
            var chsp = _ecs.GetComponent<HierarchyComponent>(child, _hierarchyCid);
            if (chsp.IsEmpty) break;
            child = chsp[0].NextSibling;
        }
        return result;
    }

    /// <summary>
    /// Reads a component by its ECS registration name. Intended for game-specific
    /// components that are not registered in the framework <see cref="IComponentRegistry"/>.
    /// Returns false if the component type is unknown or the entity lacks it.
    /// </summary>
    public bool TryGetComponent<T>(ulong entity, string componentName, out T value) where T : unmanaged
    {
        if (!_ecs.TryLookupComponent(componentName, out var cid))
        {
            value = default;
            return false;
        }
        var sp = _ecs.GetComponent<T>(entity, cid);
        if (sp.IsEmpty) { value = default; return false; }
        value = sp[0];
        return true;
    }

    /// <summary>
    /// Writes <paramref name="value"/> into the component the framework's
    /// <see cref="IComponentRegistry"/> has registered for <typeparamref name="T"/>,
    /// attaching it when the entity does not carry it yet. Any domain's node type
    /// (not just Framework's own) calls this from its own assembly's <c>OnBind</c>.
    /// </summary>
    public void Set<T>(ulong entity, in T value) where T : unmanaged
        => SetByCid(entity, _components.CidOf<T>(), in value);

    /// <summary>
    /// Writes <paramref name="value"/> into the component registered under
    /// <paramref name="cid"/>, attaching it when the entity does not carry it yet.
    /// Takes the cid directly so a caller whose component identity is a registered
    /// name rather than a managed type can write without a type-to-cid mapping.
    /// </summary>
    public void SetByCid<T>(ulong entity, uint cid, in T value) where T : unmanaged
    {
        if (_systemCtx != 0)
        {
            var existing = _ecs.GetComponent<T>(entity, cid);
            if (!existing.IsEmpty) { existing[0] = value; return; }
            if (Runtime.SystemContext.Attach(_systemCtx, entity, cid, in value)) return;
        }
        var sp = _ecs.AddComponent<T>(entity, cid);
        if (!sp.IsEmpty) sp[0] = value;
    }

    /// <summary>
    /// Registers <typeparamref name="T"/> under <paramref name="name"/>, or returns the
    /// existing cid if that name is already registered. For component types with no C
    /// header — a game-authored node's generated backing struct — this is the only
    /// registration path; engine node types resolve an already-registered name instead
    /// via <see cref="CidOfName"/>.
    /// </summary>
    public uint RegisterComponent<T>(string name) where T : unmanaged => _ecs.RegisterComponent<T>(name);

    /// <summary>
    /// Deferred-attaches component <paramref name="cid"/> to <paramref name="entity"/>
    /// with <paramref name="value"/>, using <paramref name="view"/>'s system context.
    /// The sanctioned channel for a script to write ECS data its own <c>OnUpdate</c>
    /// call doesn't already own by binding (e.g. queuing a UI quad) — <see cref="View"/>
    /// keeps its context internal, so this is the only path to it.
    /// </summary>
    public bool Attach<T>(in View view, ulong entity, uint cid, in T value) where T : unmanaged =>
        KernelEngine.Runtime.SystemContext.Attach(view.SystemContext, entity, cid, in value);

    /// <summary>Resolves the cid a component is registered under, or throws when the name is unknown.</summary>
    public uint CidOfName(string name) =>
        _ecs.TryLookupComponent(name, out var cid)
            ? cid
            : throw new InvalidOperationException($"Component '{name}' is not registered.");

    /// <summary>
    /// Reads the component registered under <paramref name="cid"/> straight from the ECS.
    /// Mirrors <see cref="SetByCid{T}"/> — a caller whose component identity is a registered
    /// name reads the live value the same way it writes it, never through a managed cache.
    /// </summary>
    public bool TryGetByCid<T>(ulong entity, uint cid, out T value) where T : unmanaged
    {
        var sp = _ecs.GetComponent<T>(entity, cid);
        if (sp.IsEmpty) { value = default; return false; }
        value = sp[0];
        return true;
    }

    internal bool TryGet<T>(ulong entity, out T value) where T : unmanaged
    {
        var sp = _ecs.GetComponent<T>(entity, _components.CidOf<T>());
        if (sp.IsEmpty) { value = default; return false; }
        value = sp[0];
        return true;
    }

    /// <summary>
    /// Calls <see cref="Node.OnReady"/> on every node in reverse insertion order
    /// (children come after parents in a DFS scene load, so reversing gives
    /// children-before-parents ordering). Called by <see cref="SceneRouter"/> after
    /// the scene file is fully loaded.
    /// </summary>
    internal void TriggerReady()
    {
        for (int i = _allNodes.Count - 1; i >= 0; i--)
            _allNodes[i].OnReady();
    }

    /// <summary>
    /// Reads the <c>[entity.properties]</c> block declared in the scene file for
    /// <paramref name="entity"/>. Delegates to <see cref="World.TryGetProperties"/>.
    /// </summary>
    internal bool TryGetProperties(ulong entity, out VariantReader reader)
        => _world.TryGetProperties(entity, out reader);
}
