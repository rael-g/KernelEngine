using System.Text;
using KernelEngine.Ecs;

namespace KernelEngine.Framework;

/// <summary>
/// Node-aware facade over <see cref="World"/>. Game code calls <see cref="AddNode{T}"/>
/// to spawn entities and attach components; every entity is created through the
/// native <see cref="SceneTree"/> so hierarchy and name are wired at the C level.
/// </summary>
public sealed class NodeWorld : ISignalDeclarer
{
    private readonly World              _world;
    private readonly IEcsRegistry       _ecs;
    private readonly uint               _nameCid;

    private readonly HashSet<Type> _announcedBehaviors = new();

    /// <summary>
    /// Which entity carries which node, held natively so a runtime in another
    /// language sees the same bindings instead of keeping a second map of its own.
    /// </summary>
    private readonly ScriptHost _scripts;

    private readonly Dictionary<Type, uint> _scriptTypes = new();

    /// <summary>
    /// Roots each bound node for the native side, which stores the pointer and never
    /// dereferences it. A managed object moves, so what crosses the boundary is the
    /// handle rather than the reference.
    /// </summary>
    private readonly Dictionary<ulong, System.Runtime.InteropServices.GCHandle> _roots = new();

    /// <summary>
    /// Raised the first time a node of a given type registers behavior. The host
    /// listens so it can give that type its own runtime system: behavior access is a
    /// property of the node type, so one system per type is what lets the scheduler
    /// see the reach instead of lumping every script into one opaque system.
    /// </summary>
    internal event Action<Type>? BehaviorTypeAdded;

    /// <summary>
    /// How many entities are bound as <paramref name="type"/>. Asked instead of counting
    /// <see cref="BehaviorsOf"/>, which would build a list of every instance to learn its
    /// length — on the tick path that is a per-frame allocation the size of the scene.
    /// </summary>
    internal int BoundCountOf(Type type) =>
        _scriptTypes.TryGetValue(type, out var id) ? (int)_scripts.InstanceCount(id) : 0;

    /// <summary>
    /// The bound nodes of one type, read from the script host rather than from a list
    /// kept here. A second list would be a copy of the bindings that only this language
    /// can see, and that goes stale the moment anything else unbinds one of them.
    /// </summary>
    internal unsafe List<Node> BehaviorsOf(Type type)
    {
        var nodes = new List<Node>();
        if (!_scriptTypes.TryGetValue(type, out var id)) return nodes;

        uint count = 0;
        var entities = _scripts.Instances(id, &count);
        for (uint i = 0; i < count; i++)
            if (NodeOf(entities[i]) is { } node) nodes.Add(node);
        return nodes;
    }

    /// <summary>
    /// Every currently-bound node. A caller needing its own node type filters
    /// this with <c>OfType&lt;T&gt;()</c> — NodeWorld has no per-domain knowledge.
    /// </summary>
    public IReadOnlyList<Node> AllNodes
    {
        get
        {
            var all = new List<Node>();
            foreach (var type in _scriptTypes.Keys) all.AddRange(BehaviorsOf(type));
            return all;
        }
    }

    [ThreadStatic] private static nint _systemCtx;

    /// <summary>
    /// Scopes <see cref="AddNode{T}"/>/<see cref="DestroyNode"/> to a running
    /// system's context for the duration of the returned handle, so structural
    /// changes defer to the wave barrier. Restores the prior value on dispose.
    /// <para>
    /// The context belongs to the thread running the system, not to the world: the
    /// scheduler runs the systems of one wave concurrently, and a world-wide field
    /// would hand one system the context of another. A world reached from two threads
    /// at once is the normal case, not the exceptional one.
    /// </para>
    /// </summary>
    internal SystemCtxScope EnterSystem(nint ctx) => new(ctx);

    internal readonly ref struct SystemCtxScope
    {
        private readonly nint _previous;
        public SystemCtxScope(nint ctx)
        {
            _previous  = _systemCtx;
            _systemCtx = ctx;
        }
        public void Dispose() => _systemCtx = _previous;
    }

    /// <remarks>
    /// Announced after the binding reaches the host, never before: what the announcement
    /// carries is a type, and the first thing a listener does with a type is ask for an
    /// instance of it. A node the host has not been told about yet is a type with no
    /// instances, and the listener would be reading an empty answer about a node that
    /// exists.
    /// </remarks>
    private void AnnounceBehavior(Node node)
    {
        if (!node.HasBehavior) return;
        var type = node.GetType();
        if (_announcedBehaviors.Add(type)) BehaviorTypeAdded?.Invoke(type);
    }

    private readonly uint _nativeTransformCid;
    private readonly uint _hierarchyCid;

    private readonly KernelEngine.Logger.ILogger? _logger;
    private readonly HashSet<string> _reportedBorrows = new();
    private readonly Dictionary<Type, int> _lastBoundCount = new();

    /// <summary>
    /// Reports a borrow that resolved to nothing, once per node-and-name pair.
    /// </summary>
    /// <remarks>
    /// An unresolved borrow is indistinguishable from a working one at the call site —
    /// every method on it is a no-op — so the node just stops doing part of its job with
    /// nothing said. Reported once because resolution runs every tick.
    /// </remarks>
    internal void ReportUnresolvedBorrow(Node owner, string kind, string typeName, string name)
    {
        if (_logger is null) return;
        if (!_reportedBorrows.Add($"{owner.Entity}/{kind}/{typeName}/{name}")) return;
        _logger.Log(KernelEngine.Logger.LogLevel.Warning, "scene.node",
            $"'{owner.Name}' borrows {kind}<{typeName}> named '{name}', which resolves to no node");
    }

    /// <summary>
    /// Reports a node type whose behavior ran on fewer instances than are bound,
    /// once per type. Reaching instances through a query means a query that matches
    /// nothing stops the behavior with no symptom other than the node quietly doing
    /// nothing — the failure a scheduler cannot distinguish from a node with nothing
    /// to do, which is why it has to be said out loud.
    /// </summary>
    /// <remarks>
    /// Only judged on a tick where the type's instance count did not just change. A node
    /// added from inside a system defers its entity's components to the wave barrier, so
    /// on that one tick it is bound and its query legitimately reaches nothing — and
    /// reporting is latched, which would turn that single tick into a permanent
    /// accusation against a node that works.
    /// </remarks>
    internal void ReportUnmatchedBehavior(Type type, int ran, int bound)
    {
        var settled = _lastBoundCount.TryGetValue(type, out var previous) && previous == bound;
        _lastBoundCount[type] = bound;

        if (_logger is null || !settled || ran >= bound) return;
        if (!_reportedBorrows.Add($"unmatched/{type.FullName}")) return;
        _logger.Log(KernelEngine.Logger.LogLevel.Error, "scene.node",
            $"'{type.Name}' has {bound} bound instance(s) but its query reached {ran}; "
            + "the components it declares do not describe the entities it is bound to");
    }

    /// <summary>
    /// Reports a borrow that named no node and found more than one of its type.
    /// </summary>
    internal void ReportAmbiguousBorrow(Node owner, string kind, string typeName, string first, string second)
    {
        if (_logger is null) return;
        if (!_reportedBorrows.Add($"{owner.Entity}/{kind}/{typeName}/?")) return;
        _logger.Log(KernelEngine.Logger.LogLevel.Warning, "scene.node",
            $"'{owner.Name}' borrows {kind}<{typeName}> with no name, and both '{first}' and '{second}' answer to it; "
            + "give the borrow a NodeName");
    }

    private readonly Dictionary<Type, (int Stamp, uint[] Ids)> _assignableTypes = new();

    /// <summary>
    /// The script type ids whose node type is <paramref name="wanted"/> or derives from
    /// it. The native host matches one exact id, and that is deliberate: a base type
    /// standing in for its subtypes is this projection's own idea, so the set of ids a
    /// borrow accepts is widened here instead of every language sharing a contract that
    /// has to model inheritance.
    /// </summary>
    private uint[] ScriptTypesAssignableTo(Type wanted)
    {
        if (_assignableTypes.TryGetValue(wanted, out var cached) && cached.Stamp == _scriptTypes.Count)
            return cached.Ids;

        var ids = new List<uint>();
        foreach (var (clr, id) in _scriptTypes)
            if (wanted.IsAssignableFrom(clr)) ids.Add(id);

        var built = ids.ToArray();
        _assignableTypes[wanted] = (_scriptTypes.Count, built);
        return built;
    }

    /// <summary>
    /// The node below <paramref name="owner"/> bound as <paramref name="wanted"/>, or
    /// null when none is or more than one answers. Two ids answering is ambiguity the
    /// same way two nodes of one id are, so it is reported rather than resolved by
    /// picking whichever type registered first.
    /// </summary>
    internal Node? ResolveDescendant(Node owner, Type wanted, string name)
    {
        Node? found = null;
        foreach (var id in ScriptTypesAssignableTo(wanted))
        {
            var entity = _scripts.ResolveDescendant(owner.Entity, id, name);
            if (entity == 0 || NodeOf(entity) is not { } node) continue;
            if (found is not null)
            {
                ReportAmbiguousBorrow(owner, "Child", wanted.Name, found.Name, node.Name);
                return null;
            }
            found = node;
        }
        return found;
    }

    /// <summary>
    /// The nearest node above <paramref name="owner"/> bound as <paramref name="wanted"/>.
    /// </summary>
    /// <remarks>
    /// Only the single-id case goes native: the slot answers with an entity and not with
    /// its depth, so which of several candidates is nearest cannot be decided from the
    /// answers alone. Widening the slot to say so would be modelling inheritance in a
    /// contract that has none.
    /// </remarks>
    internal Node? ResolveAncestor(Node owner, Type wanted, string name)
    {
        var ids = ScriptTypesAssignableTo(wanted);
        if (ids.Length == 1)
        {
            var entity = _scripts.ResolveAncestor(owner.Entity, ids[0], name);
            return entity == 0 ? null : NodeOf(entity);
        }

        for (var ancestor = owner.Parent; ancestor is not null; ancestor = ancestor.Parent)
            if (wanted.IsInstanceOfType(ancestor) && (name.Length == 0 || ancestor.Name == name))
                return ancestor;
        return null;
    }

    private readonly SignalBus? _signals;
    private readonly Dictionary<Type, uint> _signalIds = new();

    /// <summary>The signal bus this world raises through, or null when none is registered.</summary>
    public SignalBus? Signals => _signals;

    /// <summary>
    /// Resolves the signal id for payload type <typeparamref name="T"/>, registering
    /// it on first use. The type's name and size are the identity, so a node in
    /// another language naming the same signal lands on the same id.
    /// </summary>
    internal unsafe uint SignalIdOf<T>() where T : unmanaged
    {
        if (_signalIds.TryGetValue(typeof(T), out var id)) return id;
        uint resolved = 0;
        _signals!.SignalId(typeof(T).Name, (uint)sizeof(T), &resolved);
        _signalIds[typeof(T)]     = resolved;
        _signalTypes[resolved]    = typeof(T);
        return resolved;
    }

    private readonly Dictionary<uint, Type> _signalTypes = new();

    /// <summary>
    /// Declares a payload type's signal up front, so a scene naming it resolves and a
    /// scene naming something else fails instead of inventing a signal nobody raises.
    /// </summary>
    void ISignalDeclarer.Declare<T>() => _ = SignalIdOf<T>();

    /// <summary>
    /// Hands one delivery to the node it names. A delivery whose target is no longer
    /// bound, or whose signal this world never registered a payload type for, is
    /// dropped: the bus is language-neutral, so an id raised by another runtime is a
    /// normal case here, not an error.
    /// </summary>
    internal unsafe void Deliver(in KernelEngine.Framework.Native.ke_signal_delivery delivery)
    {
        if (!_signalTypes.TryGetValue(delivery.signal_id, out var type)) return;
        if (NodeOf(delivery.target) is not { } node) return;
        node.GeneratedDeliverSignal(type,
            new ReadOnlySpan<byte>((void*)delivery.payload, (int)delivery.payload_size));
    }

    /// <summary>
    /// Wires <paramref name="source"/>'s <typeparamref name="T"/> signal to
    /// <paramref name="target"/>, which receives it through its <c>On(in T)</c>
    /// handler. Wiring the same pair twice delivers once.
    /// </summary>
    public void Connect<T>(Node source, Node target) where T : unmanaged
    {
        if (_signals is null) return;
        _signals.Connect(source.Entity, SignalIdOf<T>(), target.Entity, 0);
    }

    /// <summary>Removes a connection made by <see cref="Connect{T}"/>.</summary>
    public bool Disconnect<T>(Node source, Node target) where T : unmanaged =>
        _signals is not null && _signals.Disconnect(source.Entity, SignalIdOf<T>(), target.Entity, 0);

    internal Emit<T> EmitFor<T>(ulong source) where T : unmanaged =>
        _signals is null ? default : new Emit<T>(_signals, source, SignalIdOf<T>());

    internal NodeWorld(World world, IEcsRegistry ecs,
                       ScriptHost scripts,
                       KernelEngine.Logger.ILogger? logger = null,
                       SignalBus? signals = null)
    {
        _scripts    = scripts;
        _signals    = signals;
        _world      = world;
        _ecs        = ecs;
        _logger     = logger;
        _nameCid            = ecs.RegisterComponent<Native.ke_name_component>("name");
        _nativeTransformCid = ecs.RegisterComponent<Common.Native.ke_transform_component>("transform");
        _hierarchyCid       = ecs.RegisterComponent<Native.ke_hierarchy_component>("hierarchy");
    }

    /// <summary>
    /// Registers a node in the world: creates a native entity via the scene tree,
    /// binds the node to it, and lets the subclass materialize its components.
    /// </summary>
    public T AddNode<T>(T node, string name = "", Node? parent = null) where T : Node
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a world.");
        if (parent is not null && !parent.BelongsTo(this))
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = _world.SceneTree.CreateNode(name, parent?.Entity ?? 0, _systemCtx);
        node.BindToNodeWorld(this, entity);
        BindScript(node);
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
        if (parent is not null && !parent.BelongsTo(this))
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = _world.SceneTree.CreateNode(name, parent?.Entity ?? 0, _systemCtx);
        node.PreBind(this, entity);
        BindScript(node);
    }

    internal void CompleteAddNode(Node node) => node.CompleteBind();

    /// <summary>
    /// Resolves the native script type for a node's CLR type, registering it on first
    /// use from what the node itself declares: the components it carries and whether
    /// its behaviour reaches past its own entity.
    /// </summary>
    private uint ScriptTypeOf(Node node)
    {
        var clr = node.GetType();
        if (_scriptTypes.TryGetValue(clr, out var existing)) return existing;

        var uses = new List<NodeComponentUse>();
        node.CollectBehaviorComponents(uses);

        var cids = new List<uint>();
        foreach (var use in uses)
            if (use.Owned && _ecs.TryLookupComponent(use.Name, out var cid) && !cids.Contains(cid))
                cids.Add(cid);

        var reach = node.ReachesOnlyItself ? ScriptReach.Self : ScriptReach.Any;
        uint id = 0;
        unsafe
        {
            var owned = cids.ToArray();
            fixed (uint* p = owned)
                _scripts.RegisterType(clr.FullName ?? clr.Name, p, (uint)owned.Length, reach, &id);
        }
        _scriptTypes[clr] = id;
        return id;
    }

    private void BindScript(Node node)
    {
        var root = System.Runtime.InteropServices.GCHandle.Alloc(node);
        _roots[node.Entity] = root;
        _scripts.Bind(node.Entity, ScriptTypeOf(node), System.Runtime.InteropServices.GCHandle.ToIntPtr(root));
        AnnounceBehavior(node);
    }

    private void UnbindScript(ulong entity)
    {
        _scripts.Unbind(entity);
        if (!_roots.Remove(entity, out var root)) return;
        root.Free();
    }

    /// <summary>
    /// The node bound to <paramref name="entity"/>, or null when none is. Null is the
    /// normal answer, not a failure: an entity the scene loader made without a script,
    /// or one another language's runtime owns, carries the same components and matches
    /// the same query without any node here standing behind it.
    /// </summary>
    internal unsafe Node? NodeOf(ulong entity)
    {
        nint instance = 0;
        if (!_scripts.TryInstanceOf(entity, null, &instance) || instance == 0) return null;
        return System.Runtime.InteropServices.GCHandle.FromIntPtr(instance).Target as Node;
    }

    /// <summary>Finds a node by its exact name or path, resolved through the native scene tree.</summary>
    public Node? Find(string name)
    {
        var entity = _world.SceneTree.FindNode(name);
        return entity != 0 ? NodeOf(entity) : null;
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
        if (!node.IsBound || !node.BelongsTo(this)) return;
        var kids = node.Children.ToArray();
        for (int i = 0; i < kids.Length; i++) DestroyNode(kids[i]);

        node.OnUnbind();

        UnbindScript(node.Entity);
        _signals?.ForgetEntity(node.Entity);
        _world.SceneTree.DestroyNode(node.Entity, _systemCtx);
        node.UnbindFromNodeWorld();
    }

    /// <summary>
    /// Destroys every node currently in the world. Used by <see cref="SceneRouter"/>
    /// to flush a scene before loading the next one.
    /// </summary>
    public void Clear()
    {
        var roots = AllNodes.Where(n => n.Parent is null).ToArray();
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
        BindScript(node);
    }

    /// <summary>
    /// Reads <paramref name="entity"/>'s display name straight from <c>ke_name_component</c>
    /// — never cached, so a native rename is visible on the next read without any
    /// sync step. "" for an entity with no name (or none at all).
    /// </summary>
    internal string GetName(ulong entity)
    {
        var nsp = _ecs.GetComponent<Native.ke_name_component>(entity, _nameCid);
        if (nsp.IsEmpty) return "";
        ReadOnlySpan<sbyte> chars = nsp[0].name;
        var bytes = System.Runtime.InteropServices.MemoryMarshal.Cast<sbyte, byte>(chars);
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
        var hsp = _ecs.GetComponent<Native.ke_hierarchy_component>(entity, _hierarchyCid);
        if (hsp.IsEmpty) return null;
        var parent = hsp[0].parent;
        if (parent == 0) return null;
        return NodeOf(parent);
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
        var hsp = _ecs.GetComponent<Native.ke_hierarchy_component>(entity, _hierarchyCid);
        if (hsp.IsEmpty) return result;

        var child = hsp[0].first_child;
        while (child != 0)
        {
            if (NodeOf(child) is { } node) result.Add(node);
            var chsp = _ecs.GetComponent<Native.ke_hierarchy_component>(child, _hierarchyCid);
            if (chsp.IsEmpty) break;
            child = chsp[0].next_sibling;
        }
        return result;
    }

    /// <summary>
    /// Reads a component by its ECS registration name. Returns false if the name is
    /// unknown or the entity lacks it.
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

    /// <summary>
    /// Hands out the component's live storage rather than a copy of it, so a caller
    /// touching one field pays neither the read-back nor the write-back of the whole
    /// struct. Empty when the entity does not carry the component — including while an
    /// attach is still queued behind a wave barrier, when the value exists but its
    /// storage does not yet.
    /// </summary>
    internal Span<T> StorageByCid<T>(ulong entity, uint cid) where T : unmanaged =>
        _ecs.GetComponent<T>(entity, cid);

    /// <summary>
    /// Calls <see cref="Node.OnReady"/> on every node, deepest first, walking the
    /// scene tree rather than the order the nodes happened to be created in. A node's
    /// children are ready before it is, so a parent that inspects what is under it
    /// finds it already set up. Called by <see cref="SceneRouter"/> after the scene
    /// file is fully loaded.
    /// </summary>
    internal void TriggerReady()
    {
        foreach (var root in AllNodes)
            if (root.Parent is null) ReadyDepthFirst(root);
    }

    private static void ReadyDepthFirst(Node node)
    {
        var children = node.Children;
        for (int i = 0; i < children.Count; i++) ReadyDepthFirst(children[i]);
        node.OnReady();
    }
}
