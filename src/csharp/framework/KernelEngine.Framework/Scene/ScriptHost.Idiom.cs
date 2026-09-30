using System.Text;
using KernelEngine.Ecs;

namespace KernelEngine.Framework;

/// <summary>
/// The node-shaped face of the script host: spawning, destroying and reaching nodes,
/// in the object vocabulary this language speaks.
/// </summary>
/// <remarks>
/// It lives on the host rather than beside it because the host already owns what the
/// questions are about — which entity carries which instance, which entities a type
/// has, what a borrow resolves to. A separate class over the same facts is a second
/// place to keep them in step, which is what this one used to be.
/// </remarks>
public unsafe partial class ScriptHost : ISignalDeclarer
{
    private World              _world = null!;
    private IEcsRegistry       _ecs = null!;
    private uint                       _nameCid;

    private readonly HashSet<Type> _announcedBehaviors = new();

    private readonly Dictionary<Type, uint> _scriptTypes = new();

    /// <summary>
    /// Raised the first time a node of a given type registers behavior. The host
    /// listens so it can give that type its own runtime system: behavior access is a
    /// property of the node type, so one system per type is what lets the scheduler
    /// see the reach instead of lumping every script into one opaque system.
    /// </summary>
    internal event Action<Type>? BehaviorTypeAdded;

    /// <summary>
    /// The bound nodes of one type, read from the script host rather than from a list
    /// kept here. A second list would be a copy of the bindings that only this language
    /// can see, and that goes stale the moment anything else unbinds one of them.
    /// </summary>
    internal List<Node> BehaviorsOf(Type type)
    {
        var nodes = new List<Node>();
        if (!_scriptTypes.TryGetValue(type, out var id)) return nodes;

        foreach (var entity in Instances(id))
            if (NodeOf(entity) is { } node) nodes.Add(node);
        return nodes;
    }

    /// <summary>
    /// Every currently-bound node. A caller needing its own node type filters
    /// this with <c>OfType&lt;T&gt;()</c> — ScriptHost has no per-domain knowledge.
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

    private uint _nativeTransformCid;

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
    /// The node <paramref name="owner"/> borrows: an instance of <paramref name="wanted"/>
    /// within <paramref name="reach"/>, or null when none is or more than one answers.
    /// Two ids answering is ambiguity the same way two nodes of one id are, so neither is
    /// resolved by picking whichever type registered first.
    /// </summary>
    /// <remarks>
    /// An ancestor borrow across several ids is decided here instead: the slot answers
    /// with an entity and not with its depth, so which of several candidates is nearest
    /// cannot be read off the answers. Widening the slot to say so would be modelling
    /// inheritance in a contract that has none.
    /// </remarks>
    internal Node? Borrow(Node owner, Type wanted, string name, ScriptBorrow reach)
    {
        var ids = ScriptTypesAssignableTo(wanted);

        if (reach == ScriptBorrow.Ancestor && ids.Length != 1)
        {
            for (var ancestor = owner.Parent; ancestor is not null; ancestor = ancestor.Parent)
                if (wanted.IsInstanceOfType(ancestor) && (name.Length == 0 || ancestor.Name == name))
                    return ancestor;
            return null;
        }

        Node? found = null;
        foreach (var id in ids)
        {
            var entity = Resolve(owner.Entity, id, name, reach, out var why);
            if (why == ScriptResolve.Ambiguous) return null;
            if (entity == 0 || NodeOf(entity) is not { } node) continue;
            if (found is not null) return null;
            found = node;
        }
        return found;
    }

    private SignalBus? _signals;
    /// <summary>The signal bus this world raises through, or null when none is registered.</summary>
    public SignalBus? Signals => _signals;

    /// <summary>
    /// Resolves the signal id for payload type <typeparamref name="T"/>, registering
    /// it on first use. The type's name and size are the identity, so a node in
    /// another language naming the same signal lands on the same id.
    /// </summary>
    internal unsafe uint SignalIdOf<T>() where T : unmanaged => _signals!.SignalIdOf<T>();

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
        if (_signals!.SignalIdTypeOf(delivery.signal_id) is not { } type) return;
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

    /// <summary>
    /// Hands the host the collaborators its node-shaped surface needs, which the
    /// generated constructor cannot take: it is derived from the C factory, and the
    /// factory's business is the native host alone.
    /// </summary>
    /// <returns>The same instance, so composition reads as one expression.</returns>
    internal ScriptHost Compose(World world, IEcsRegistry ecs, SignalBus? signals = null)
    {
        _signals    = signals;
        _world      = world;
        _ecs        = ecs;
        _nameCid            = ecs.RegisterComponent<Native.ke_name_component>("name");
        _nativeTransformCid = ecs.RegisterComponent<Common.Native.ke_transform_component>("transform");
        _ = ecs.RegisterComponent<Native.ke_hierarchy_component>("hierarchy");
        return this;
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
        node.BindToScene(this, entity);
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
        var id = RegisterType(clr.FullName ?? clr.Name, cids.ToArray(), reach);
        _scriptTypes[clr] = id;
        return id;
    }

    private void BindScript(Node node)
    {
        Bind(node.Entity, ScriptTypeOf(node), node);
        AnnounceBehavior(node);
    }

    private void UnbindScript(ulong entity) => Unbind(entity);

    /// <summary>
    /// The node bound to <paramref name="entity"/>, or null when none is. Null is the
    /// normal answer, not a failure: an entity the scene loader made without a script,
    /// or one another language's runtime owns, carries the same components and matches
    /// the same query without any node here standing behind it.
    /// </summary>
    internal Node? NodeOf(ulong entity) =>
        TryInstanceOf(entity, out _, out var instance) ? instance as Node : null;

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
        node.UnbindFromScene();
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
        node.BindToScene(this, entity);
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
        var parent = _world.SceneTree.Parent(entity);
        return parent == 0 ? null : NodeOf(parent);
    }

    /// <summary>
    /// Walks <paramref name="entity"/>'s children in the order they were added,
    /// asking the scene tree for each step rather than reading the hierarchy
    /// component here. How parenthood is stored is the tree's business; a second
    /// walker over the same bytes is a second thing to fix when that changes.
    /// Skips any child with no managed <see cref="Node"/> bound to it.
    /// </summary>
    internal IReadOnlyList<Node> GetChildren(ulong entity)
    {
        var result = new List<Node>();
        var tree = _world.SceneTree;
        for (var child = tree.FirstChild(entity); child != 0; child = tree.NextSibling(child))
            if (NodeOf(child) is { } node) result.Add(node);
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
            if (Runtime.SystemCtx.Attach(_systemCtx, entity, cid, in value)) return;
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
        KernelEngine.Runtime.SystemCtx.Attach(view.SystemContext, entity, cid, in value);

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
