using KernelEngine.Ecs;


namespace KernelEngine.Framework;

/// <summary>
/// Base class for scene objects: the managed wrapper around one ECS entity, bound to it by
/// <see cref="ScriptHost.AddNode"/> or by the native scene loader, and unbound again when the
/// node is destroyed. Its properties read and write the entity's components in place.
/// </summary>
public abstract class Node
{
    /// <summary>ECS entity this node wraps. 0 while the node is not bound.</summary>
    public ulong Entity { get; private set; }

    private ScriptHost? ScriptHost { get; set; }

    /// <summary>
    /// Name of the entity, read from <c>ke_name_component</c> each time. Empty while the node is
    /// not bound.
    /// </summary>
    public string Name => ScriptHost?.GetName(Entity) ?? "";

    /// <summary>True while the node is bound to an entity.</summary>
    public bool IsBound => ScriptHost != null;

    /// <summary>
    /// Parent node, resolved from <c>ke_hierarchy_component</c> each time. Null while unbound,
    /// when this node has no parent, or when the parent entity has no managed
    /// <see cref="Framework.Node"/> bound to it.
    /// </summary>
    public Node? Parent => ScriptHost?.GetParent(Entity);

    /// <summary>
    /// Child nodes, walked from <c>ke_hierarchy_component</c> each time in creation order.
    /// Empty while unbound.
    /// </summary>
    public IReadOnlyList<Node> Children => ScriptHost?.GetChildren(Entity) ?? Array.Empty<Node>();

    /// <summary>
    /// Called once when the node is bound, after <see cref="GeneratedBind"/> has resolved this
    /// node's generated components. Base implementation is a no-op.
    /// </summary>
    protected internal virtual void OnBind(ScriptHost scriptHost) { }

    /// <summary>
    /// Called once when the node is bound, before <see cref="OnBind"/>: resolves the component id
    /// of each slot behind the node's generated properties and seeds the values authored before
    /// binding. Overridden by <c>NodePropertyGenerator</c>; base is a no-op.
    /// </summary>
    protected internal virtual void GeneratedBind(ScriptHost scriptHost) { }

    /// <summary>
    /// Called once after every entity of the loaded scene file exists and every component block
    /// is applied, so the sibling nodes and authored components can be looked up. Base
    /// implementation is a no-op.
    /// </summary>
    protected internal virtual void OnReady() { }

    /// <summary>
    /// Called every simulation tick on a bound node of a type that has behavior. Base
    /// implementation is a no-op.
    /// </summary>
    protected internal virtual void OnUpdate(in View view) { }

    /// <summary>
    /// Called every fixed step on a bound node of a type that has fixed-step behavior, with the
    /// step's duration in the view. Base implementation is a no-op.
    /// </summary>
    protected internal virtual void OnFixedUpdate(in View view) { }

    /// <summary>
    /// Called once when the node is removed from the world, children first. Base implementation
    /// is a no-op.
    /// </summary>
    protected internal virtual void OnUnbind() { }

    /// <summary>
    /// True when the node type has per-frame logic and so gets a per-frame system. Overridden by
    /// <c>NodePropertyGenerator</c> for a type that declares <c>Update</c> or overrides
    /// <see cref="OnUpdate"/>; base is false.
    /// </summary>
    protected internal virtual bool HasBehavior => false;

    /// <summary>
    /// True when the node type has fixed-step logic and so gets a fixed-step system. Overridden by
    /// <c>NodePropertyGenerator</c> for a type that declares <c>FixedUpdate</c> or overrides
    /// <see cref="OnFixedUpdate"/>; base is false.
    /// </summary>
    protected internal virtual bool HasFixedBehavior => false;

    /// <summary>
    /// Whether this node type's behavior touches nothing beyond its own entity, so that its
    /// instances may run concurrently. False for a node that borrows another node, and for a
    /// hand-written <see cref="OnUpdate"/> or <see cref="OnFixedUpdate"/>. Base is false.
    /// </summary>
    protected internal virtual bool ReachesOnlyItself => false;

    /// <summary>
    /// Appends the ECS components this node type reaches and how it reaches them. An override
    /// calls the base first and then adds its own, so an inherited set accumulates down the
    /// chain.
    /// </summary>
    protected internal virtual void CollectBehaviorComponents(List<NodeComponentUse> into) { }

    /// <summary>
    /// Creates <paramref name="child"/> as this node's child, under
    /// <paramref name="name"/>, which a <see cref="Borrow{T}"/> call can resolve against.
    /// </summary>
    /// <returns>
    /// The same instance, now bound.
    /// </returns>
    /// <exception cref="InvalidOperationException">This node is not bound yet.</exception>
    protected T AddChild<T>(T child, string name = "") where T : Node
    {
        if (ScriptHost is null)
            throw new InvalidOperationException(
                $"'{GetType().Name}' cannot add a child before it is added to a world.");
        return ScriptHost.AddNode(child, name, parent: this);
    }

    /// <summary>
    /// Attaches a component to this entity from inside a behavior, recorded in the running
    /// system's command queue so the change applies at the wave barrier. For a component this
    /// node's own type does not declare.
    /// </summary>
    protected void Attach<T>(in View view, uint cid, in T value) where T : unmanaged =>
        view.Commands.Attach(Entity, cid, in value);

    /// <summary>
    /// Removes this node and everything under it from the world. Does nothing when the node is
    /// not bound.
    /// </summary>
    public void Destroy() => ScriptHost?.DestroyNode(this);

    /// <summary>
    /// Reads one of this entity's components by its ECS registration name, for a component this
    /// node's own type does not declare. Returns false when the node is not bound or the entity
    /// does not carry the component.
    /// </summary>
    protected bool TryGetComponent<T>(string componentName, out T value) where T : unmanaged
    {
        if (ScriptHost is not null) return ScriptHost.TryGetComponent(Entity, componentName, out value);
        value = default;
        return false;
    }

    /// <summary>
    /// Resolves a borrow within <paramref name="reach"/>, anew on every call. Returns null when
    /// nothing matches or when more than one node does. An empty <paramref name="name"/>
    /// resolves by type alone.
    /// </summary>
    protected internal T? Borrow<T>(string name, ScriptBorrow reach) where T : Node =>
        ScriptHost?.Borrow(this, typeof(T), name, reach) as T;

    /// <summary>
    /// Resolves an <see cref="Emit{T}"/> borrow: the right to raise signal
    /// <typeparamref name="T"/> from this node.
    /// </summary>
    protected internal Emit<T> BorrowEmit<T>() where T : unmanaged =>
        ScriptHost is null ? default : ScriptHost.EmitFor<T>(Entity);

    internal void UnbindFromScene()
    {
        ScriptHost = null;
        Entity = 0;
    }

    /// <summary>Whether this node is bound to <paramref name="world"/>.</summary>
    internal bool BelongsTo(ScriptHost world) => ReferenceEquals(ScriptHost, world);

    internal void BindToScene(ScriptHost scriptHost, ulong entity)
    {
        PreBind(scriptHost, entity);
        CompleteBind();
    }

    internal void PreBind(ScriptHost scriptHost, ulong entity)
    {
        ScriptHost = scriptHost;
        Entity = entity;
    }

    /// <summary>
    /// Seeds one of this node's components at bind time: writes the value authored before
    /// binding, unless the entity already carries that component, in which case the existing
    /// value is kept.
    /// </summary>
    protected internal void GeneratedSeed<T>(uint cid, in T state) where T : unmanaged
    {
        if (ScriptHost!.TryGetByCid<T>(Entity, cid, out _)) return;
        ScriptHost.SetByCid(Entity, cid, in state);
    }

    /// <summary>
    /// Writes one of this node's component values.
    /// </summary>
    protected internal void GeneratedSet<T>(uint cid, in T state) where T : unmanaged =>
        ScriptHost!.SetByCid(Entity, cid, in state);

    /// <summary>
    /// Reads one of this node's component values. Counterpart to <see cref="GeneratedSet{T}"/>.
    /// </summary>
    protected internal bool GeneratedTryGet<T>(uint cid, out T state) where T : unmanaged =>
        ScriptHost!.TryGetByCid(Entity, cid, out state);

    /// <summary>
    /// Returns a reference to one of this node's components in place.
    /// <paramref name="live"/> reports whether the reference is the component's own storage;
    /// when false it is <paramref name="authored"/>, the node's pre-bind value, which is the
    /// case before binding and while an attach is queued behind a wave barrier, and a writer
    /// must then publish through <see cref="GeneratedSet{T}"/>.
    /// </summary>
    protected internal ref T GeneratedStorage<T>(uint cid, ref T authored, out bool live) where T : unmanaged
    {
        if (ScriptHost is not null)
        {
            var storage = ScriptHost.StorageByCid<T>(Entity, cid);
            if (!storage.IsEmpty)
            {
                live = true;
                return ref storage[0];
            }
        }
        live = false;
        return ref authored;
    }

    /// <summary>
    /// Hands this node one delivered signal, calling the <c>On</c> method whose parameter type is
    /// <paramref name="payloadType"/>. Overridden by <c>NodePropertyGenerator</c> for node types
    /// that declare handlers; base is a no-op.
    /// </summary>
    protected internal virtual void GeneratedDeliverSignal(Type payloadType, ReadOnlySpan<byte> payload) { }

    internal void CompleteBind()
    {
        GeneratedBind(ScriptHost!);
        OnBind(ScriptHost!);
    }
}
