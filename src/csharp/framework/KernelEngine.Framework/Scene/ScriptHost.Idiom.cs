using System.Text;
using KernelEngine.Ecs;

namespace KernelEngine.Framework;

/// <summary>
/// The managed face of the native script host: creates, destroys and finds <see cref="Node"/>
/// objects, binds each to its entity as an instance of a script type registered per node class,
/// resolves borrows and raises and delivers signals. Each bound node is held by a GC handle
/// stored as the native instance; a node unbound inside a system has its handle freed two
/// calls of <c>ReleaseRetired</c> later, so a system still reading it is not left with a freed
/// handle. The system running on the current thread scopes <see cref="AddNode{T}"/> and
/// <see cref="DestroyNode"/> to its command queue, so structural changes made there apply at the
/// wave barrier.
/// </summary>
public unsafe partial class ScriptHost : ISignalDeclarer
{
    private World              _world = null!;
    private IEcsRegistry       _ecs = null!;
    private uint                       _nameCid;

    private readonly HashSet<Type> _announcedBehaviors = new();

    private readonly System.Collections.Concurrent.ConcurrentDictionary<Type, uint> _scriptTypes = new();
    private readonly object _typeGate = new();
    private readonly System.Collections.Concurrent.ConcurrentQueue<(long Epoch, System.Runtime.InteropServices.GCHandle Handle)> _retired = new();
    private long _epoch;

    internal event Action<Type, Node>? BehaviorTypeAdded;

    /// <summary>The bound nodes of one type, read from the native host on each call.</summary>
    internal List<Node> BehaviorsOf(Type type)
    {
        var nodes = new List<Node>();
        if (!_scriptTypes.TryGetValue(type, out var id)) return nodes;

        foreach (var entity in Instances(id))
            if (NodeOf(entity) is { } node) nodes.Add(node);
        return nodes;
    }

    /// <summary>
    /// Every currently bound node, in no defined order.
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

    [ThreadStatic] private static KernelEngine.Ecs.EcsCommands? _commands;

    /// <summary>
    /// Scopes <see cref="AddNode{T}"/> and <see cref="DestroyNode"/> to a running system's command
    /// queue on the current thread until the returned scope is disposed, so structural changes
    /// defer to the wave barrier. Disposing restores the previous queue.
    /// </summary>
    internal SystemCtxScope EnterSystem(nint ctx) => new(ctx);

    internal readonly ref struct SystemCtxScope
    {
        private readonly KernelEngine.Ecs.EcsCommands? _previous;
        public SystemCtxScope(nint ctx)
        {
            _previous = _commands;
            _commands = ctx == 0 ? null : KernelEngine.Runtime.SystemCtx.Of(ctx).Commands;
        }
        public void Dispose() => _commands = _previous;
    }

    private void AnnounceBehavior(Node node)
    {
        if (!node.HasBehavior) return;
        var type = node.GetType();
        bool first;
        lock (_announcedBehaviors) first = _announcedBehaviors.Add(type);
        if (first) BehaviorTypeAdded?.Invoke(type, node);
    }

    private uint _nativeTransformCid;

    private readonly System.Collections.Concurrent.ConcurrentDictionary<Type, (int Stamp, uint[] Ids)> _assignableTypes = new();

    /// <summary>
    /// The script type ids whose node type is <paramref name="wanted"/> or derives from it.
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
    /// within <paramref name="reach"/>, or null when none is or more than one answers, whether
    /// the candidates share a script type or not. The native host is asked once per script type
    /// that is <paramref name="wanted"/> or derives from it; an ancestor borrow whose number of
    /// such types is not one is resolved by walking the parents here.
    /// </summary>
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
    /// <summary>The signal bus this host raises through, or null when none is registered.</summary>
    public SignalBus? Signals => _signals;

    /// <summary>
    /// Resolves the signal id for payload type <typeparamref name="T"/>, registering it on first
    /// use. The type's name and size are the identity of the signal.
    /// </summary>
    internal unsafe uint SignalIdOf<T>() where T : unmanaged => _signals!.SignalIdOf<T>();

    /// <summary>
    /// Registers the signal of a payload type, so that a scene can connect it by name.
    /// </summary>
    void ISignalDeclarer.Declare<T>() => _ = SignalIdOf<T>();

    /// <summary>
    /// Hands one delivery to the node it names. A delivery whose target is no longer bound, or
    /// whose signal this world has no payload type for, is dropped.
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

    /// <summary>
    /// Removes a connection made by <see cref="Connect{T}"/>; false when there was none or no
    /// signal bus is registered.
    /// </summary>
    public bool Disconnect<T>(Node source, Node target) where T : unmanaged =>
        _signals is not null && _signals.Disconnect(source.Entity, SignalIdOf<T>(), target.Entity, 0);

    internal Emit<T> EmitFor<T>(ulong source) where T : unmanaged =>
        _signals is null ? default : new Emit<T>(_signals, source, SignalIdOf<T>());

    /// <summary>
    /// Gives the host the world, the ECS registry and the optional signal bus, and registers the
    /// name, transform and hierarchy components.
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
        StateCid = ecs.RegisterComponent<ScriptHostState>("scene.script_host");
        return this;
    }

    /// <summary>
    /// The component no entity carries that stands for this host's own state. A system that
    /// changes the host outside a node's components names it as written, so the runtime never runs
    /// two such systems in one wave.
    /// </summary>
    public uint StateCid { get; private set; }

    private struct ScriptHostState;

    /// <summary>
    /// Creates the entity of a node under <paramref name="parent"/>, deferred when a system
    /// context is current.
    /// </summary>
    private ulong CreateEntity(string name, Node? parent)
    {
        var parentEntity = parent?.Entity ?? 0;
        return _commands is { } commands
            ? _world.SceneTree.CreateNodeDeferred(name, parentEntity, CommandsHandle(commands))
            : _world.SceneTree.CreateNode(name, parentEntity);
    }

    private static unsafe nint CommandsHandle(KernelEngine.Ecs.EcsCommands commands) =>
        (nint)((KernelEngine.Ecs.INativeEcsCommands)commands).Native;

    /// <summary>
    /// Creates an entity named <paramref name="name"/> under <paramref name="parent"/> (the root
    /// when null), binds <paramref name="node"/> to it and returns the node. Inside a system the
    /// entity and binding are recorded and apply at the wave barrier.
    /// </summary>
    /// <exception cref="InvalidOperationException">The node is already bound, or the parent
    /// belongs to another world.</exception>
    public T AddNode<T>(T node, string name = "", Node? parent = null) where T : Node
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a world.");
        if (parent is not null && !parent.BelongsTo(this))
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = CreateEntity(name, parent);
        node.BindToScene(this, entity);
        BindScript(node);
        return node;
    }

    /// <summary>
    /// First half of <see cref="AddNode{T}"/>: creates the entity and binds the node to it without
    /// calling its <see cref="Node.OnBind"/>, which <see cref="CompleteAddNode"/> does.
    /// </summary>
    internal void PreAddNode(Node node, string name, Node? parent)
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a world.");
        if (parent is not null && !parent.BelongsTo(this))
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = CreateEntity(name, parent);
        node.PreBind(this, entity);
        BindScript(node);
    }

    internal void CompleteAddNode(Node node) => node.CompleteBind();

    /// <summary>
    /// Returns the native script type of a node's CLR type, registering it on first use with the
    /// components the node owns and whether its behavior reaches only its own entity. The type
    /// name is the full name of the CLR type.
    /// </summary>
    private uint ScriptTypeOf(Node node)
    {
        var clr = node.GetType();
        if (_scriptTypes.TryGetValue(clr, out var existing)) return existing;
        lock (_typeGate)
        {
            if (_scriptTypes.TryGetValue(clr, out existing)) return existing;
            return RegisterTypeFor(clr, node);
        }
    }

    private uint RegisterTypeFor(Type clr, Node node)
    {
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
        var type = ScriptTypeOf(node);
        if (_commands is { } commands) BindDeferred(node.Entity, type, node, commands);
        else Bind(node.Entity, type, node);
        AnnounceBehavior(node);
    }

    private void BindDeferred(ulong entity, uint type, Node node, KernelEngine.Ecs.EcsCommands commands)
    {
        var handle = System.Runtime.InteropServices.GCHandle.Alloc(node);
        KernelEngine.Common.Native.ke_error* err = null;
        if (!Handle->bind_deferred(Handle, entity, type, (void*)System.Runtime.InteropServices.GCHandle.ToIntPtr(handle),
                (KernelEngine.Ecs.Native.ke_ecs_commands*)CommandsHandle(commands), &err))
        {
            handle.Free();
            throw NativeErrors.FromNative(err, "bind_deferred");
        }
        _rooted[entity] = handle;
    }

    private void UnbindScript(ulong entity)
    {
        if (_commands is not { } commands)
        {
            Unbind(entity);
            return;
        }
        KernelEngine.Common.Native.ke_error* err = null;
        if (!Handle->unbind_deferred(Handle, entity, (KernelEngine.Ecs.Native.ke_ecs_commands*)CommandsHandle(commands), &err))
            throw NativeErrors.FromNative(err, "unbind_deferred");
        if (_rooted.TryRemove(entity, out var handle)) _retired.Enqueue((Interlocked.Read(ref _epoch), handle));
    }

    internal void ReleaseRetired()
    {
        var now = Interlocked.Increment(ref _epoch);
        while (_retired.TryPeek(out var next) && next.Epoch + 2 <= now && _retired.TryDequeue(out var due))
            due.Handle.Free();
    }

    /// <summary>
    /// The node bound to <paramref name="entity"/>, or null when none is.
    /// </summary>
    internal Node? NodeOf(ulong entity) =>
        TryInstanceOf(entity, out _, out var instance) ? instance as Node : null;

    /// <summary>Finds a node by its name or path, resolved through the native scene tree.</summary>
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
    /// Removes <paramref name="node"/> and its children, children first, calling
    /// <see cref="Node.OnUnbind"/> on each, then destroys the native entities and clears the
    /// bindings. Does nothing for a node that is not bound to this host.
    /// </summary>
    public void DestroyNode(Node node)
    {
        if (!node.IsBound || !node.BelongsTo(this)) return;
        var kids = node.Children.ToArray();
        for (int i = 0; i < kids.Length; i++) DestroyNode(kids[i]);

        node.OnUnbind();

        UnbindScript(node.Entity);
        _signals?.ForgetEntity(node.Entity);
        if (_commands is { } commands)
            _world.SceneTree.DestroyNodeDeferred(node.Entity, CommandsHandle(commands));
        else
            _world.SceneTree.DestroyNode(node.Entity);
        node.UnbindFromScene();
    }

    /// <summary>
    /// Destroys every node currently in the world.
    /// </summary>
    public void Clear()
    {
        var roots = AllNodes.Where(n => n.Parent is null).ToArray();
        for (int i = 0; i < roots.Length; i++) DestroyNode(roots[i]);
    }

    /// <summary>
    /// Binds a node to an entity that already exists, such as one made by the native scene
    /// loader, and calls <see cref="Node.OnBind"/>.
    /// </summary>
    internal void BindNativeEntity(Node node, ulong entity)
    {
        node.BindToScene(this, entity);
        BindScript(node);
    }

    /// <summary>
    /// Reads the name of <paramref name="entity"/> from <c>ke_name_component</c>; empty for an
    /// entity with no name.
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
    /// Resolves the parent node of <paramref name="entity"/>. Null when the entity has no parent,
    /// or when the parent entity has no managed <see cref="Node"/> bound to it.
    /// </summary>
    internal Node? GetParent(ulong entity)
    {
        var parent = _world.SceneTree.Parent(entity);
        return parent == 0 ? null : NodeOf(parent);
    }

    /// <summary>
    /// The children of <paramref name="entity"/> in creation order, walked through the scene
    /// tree. Skips any child with no managed <see cref="Node"/> bound to it.
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
    /// <paramref name="cid"/>, attaching it when the entity does not carry it yet. Inside a
    /// system, an attach is recorded and applies at the wave barrier.
    /// </summary>
    public void SetByCid<T>(ulong entity, uint cid, in T value) where T : unmanaged
    {
        if (_commands is { } commands)
        {
            var existing = _ecs.GetComponent<T>(entity, cid);
            if (!existing.IsEmpty) { existing[0] = value; return; }
            commands.Attach(entity, cid, in value);
            return;
        }
        var sp = _ecs.AddComponent<T>(entity, cid);
        if (!sp.IsEmpty) sp[0] = value;
    }

    /// <summary>
    /// Registers <typeparamref name="T"/> under <paramref name="name"/>, or returns the existing
    /// cid if that name is already registered.
    /// </summary>
    public uint RegisterComponent<T>(string name) where T : unmanaged => _ecs.RegisterComponent<T>(name);

    /// <summary>
    /// Attaches component <paramref name="cid"/> to <paramref name="entity"/> with
    /// <paramref name="value"/> through the command queue of <paramref name="view"/>, so it
    /// applies at the wave barrier.
    /// </summary>
    public void Attach<T>(in View view, ulong entity, uint cid, in T value) where T : unmanaged =>
        view.Commands.Attach(entity, cid, in value);

    /// <summary>Returns the cid registered under the name.</summary>
    /// <exception cref="InvalidOperationException">No component has that name.</exception>
    public uint CidOfName(string name) =>
        _ecs.TryLookupComponent(name, out var cid)
            ? cid
            : throw new InvalidOperationException($"Component '{name}' is not registered.");

    /// <summary>
    /// Reads a copy of the component registered under <paramref name="cid"/>; false when the
    /// entity does not carry it.
    /// </summary>
    public bool TryGetByCid<T>(ulong entity, uint cid, out T value) where T : unmanaged
    {
        var sp = _ecs.GetComponent<T>(entity, cid);
        if (sp.IsEmpty) { value = default; return false; }
        value = sp[0];
        return true;
    }

    /// <summary>
    /// The component's live storage rather than a copy. Empty when the entity does not carry the
    /// component, including while an attach is still queued behind a wave barrier.
    /// </summary>
    internal Span<T> StorageByCid<T>(ulong entity, uint cid) where T : unmanaged =>
        _ecs.GetComponent<T>(entity, cid);

    /// <summary>
    /// Calls <see cref="Node.OnReady"/> on every node walking the scene tree, a node's children
    /// before the node.
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
