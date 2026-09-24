using KernelEngine.Ecs;


namespace KernelEngine.Framework;

/// <summary>
/// Base class for game-facing scene objects. A Node is the managed wrapper
/// around an ECS entity. Game code instantiates subclasses with init properties
/// (object-initializer syntax) and hands them to <see cref="ScriptHost.AddNode"/>;
/// AddNode creates the native entity and asks the node to materialize its components.
/// </summary>
public abstract class Node
{
    /// <summary>ECS entity this node wraps. 0 before AddNode.</summary>
    public ulong Entity { get; private set; }

    /// <summary>
    /// The world that owns this node. Null before AddNode.
    /// </summary>
    /// <remarks>
    /// Not part of a node's surface on purpose. Handing a node the whole world so
    /// it can create one child is granting access to everything to use almost
    /// nothing; a node that wants a child says so with <see cref="AddChild{T}"/>,
    /// and a node that wants to give someone else a child asks that node for it.
    /// </remarks>
    private ScriptHost? ScriptHost { get; set; }

    /// <summary>
    /// Display name (debug / lookups). Read live from <c>ke_name_component</c> —
    /// not a managed copy, so it can never drift from the entity's actual name.
    /// "" before AddNode binds this node.
    /// </summary>
    public string Name => ScriptHost?.GetName(Entity) ?? "";

    /// <summary>True after AddNode binds this node to an entity.</summary>
    public bool IsBound => ScriptHost != null;

    /// <summary>
    /// Parent node, resolved live from <c>ke_hierarchy_component</c>. Null before
    /// binding, when this node has no parent, or when the parent entity has no
    /// managed <see cref="Framework.Node"/> bound to it.
    /// </summary>
    public Node? Parent => ScriptHost?.GetParent(Entity);

    /// <summary>
    /// Child nodes, walked live from <c>ke_hierarchy_component</c> in insertion
    /// order. Empty before binding.
    /// </summary>
    public IReadOnlyList<Node> Children => ScriptHost?.GetChildren(Entity) ?? Array.Empty<Node>();

    /// <summary>
    /// Called once by <see cref="ScriptHost.AddNode"/> after the entity has been
    /// created and after <see cref="GeneratedBind"/> has materialized this node's
    /// generated components. Override to materialize components the generator does
    /// not know about. Base implementation is a no-op.
    /// </summary>
    protected internal virtual void OnBind(ScriptHost scriptHost) { }

    /// <summary>
    /// Materializes the components this node's generated properties are backed by:
    /// resolves each component id and seeds the values authored before binding.
    /// Overridden by <c>NodePropertyGenerator</c>; base is a no-op.
    /// </summary>
    /// <remarks>
    /// Separate from <see cref="OnBind"/> so the generator and the node's own author
    /// are never competing for the same method — a node that needs both keeps both.
    /// </remarks>
    protected internal virtual void GeneratedBind(ScriptHost scriptHost) { }

    /// <summary>
    /// Called once after every entity in the scene is loaded and every component
    /// block applied. Override to look up sibling nodes, or to act on a component
    /// the scene authored — both are guaranteed to exist at this point.
    /// Base implementation is a no-op.
    /// </summary>
    protected internal virtual void OnReady() { }

    /// <summary>
    /// Called every simulation tick on bound nodes. Default is a no-op so
    /// only nodes that override this pay the virtual-call cost each frame.
    /// </summary>
    protected internal virtual void OnUpdate(in View view) { }

    /// <summary>
    /// Called once when the node is removed from the world. Scripts that own
    /// external resources release them here. Base implementation is a no-op.
    /// </summary>
    protected internal virtual void OnUnbind() { }

    /// <summary>
    /// True when the subclass has per-frame logic — <see cref="OnUpdate"/> is
    /// overridden. Decided at compile time, not by reflecting on the instance:
    /// a hand-written subclass overrides this the same way it overrides
    /// <see cref="OnUpdate"/> itself; a generated subclass gets the override
    /// emitted by <c>NodePropertyGenerator</c> when it detects the user's own
    /// partial declares <c>OnUpdate</c>. Base is false so a node with no
    /// override never enters <see cref="Framework.ScriptHost.Behaviors"/>.
    /// </summary>
    protected internal virtual bool HasBehavior => false;

    /// <summary>
    /// Whether this node type's behavior touches nothing beyond its own entity, which is
    /// what lets the host run its instances concurrently: two instances are two entities,
    /// so their work cannot overlap. False for a node that borrows another node, and for
    /// a hand-written <see cref="OnUpdate"/>, whose reach the generator cannot see.
    /// Base is false so anything unproven runs serially.
    /// </summary>
    protected internal virtual bool ReachesOnlyItself => false;

    /// <summary>
    /// Appends the ECS components this node type reaches and how it reaches them, so
    /// the scheduler can order its behavior against the other writers of those
    /// components instead of trusting phase placement. An override calls the base
    /// first and then adds its own, which is what makes an inherited component set
    /// accumulate down the chain.
    /// </summary>
    protected internal virtual void CollectBehaviorComponents(List<NodeComponentUse> into) { }

    /// <summary>
    /// Declares every payload type this node type emits or handles, so a signal a
    /// scene may legitimately name exists before any scene is read. Without it a
    /// signal comes into being only when something first emits it, which makes a
    /// scene naming a real signal indistinguishable from one naming a typo.
    /// Accumulates down the chain the same way <see cref="CollectBehaviorComponents"/>
    /// does.
    /// </summary>
    protected internal virtual void CollectSignalTypes(ISignalDeclarer into) { }

    /// <summary>
    /// Creates <paramref name="child"/> as this node's child, under
    /// <paramref name="name"/>. The name is what a <see cref="Child{T}"/> borrow
    /// resolves against, so two children of the same type are told apart by it.
    /// </summary>
    /// <returns>
    /// The same instance, now bound — so it can be kept in a field without a
    /// second lookup.
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
    /// Attaches a component to this entity from inside a behavior, routed through
    /// the running system so the structural change defers to the wave barrier.
    /// For a component this node's own type does not declare — one the node
    /// produces each tick for another domain's pass to read.
    /// </summary>
    protected bool Attach<T>(in View view, uint cid, in T value) where T : unmanaged =>
        KernelEngine.Runtime.SystemContext.Attach(view.SystemContext, Entity, cid, in value);

    /// <summary>
    /// Removes this node and everything under it from the world. Destroying a
    /// node other than <c>this</c> means holding a reference to it and asking it
    /// — the same way adding a child does.
    /// </summary>
    public void Destroy() => ScriptHost?.DestroyNode(this);

    /// <summary>
    /// Reads one of this entity's components by its ECS registration name, for a
    /// component this node's own type does not declare (one a scene block or
    /// another domain put there).
    /// </summary>
    protected bool TryGetComponent<T>(string componentName, out T value) where T : unmanaged
    {
        if (ScriptHost is not null) return ScriptHost.TryGetComponent(Entity, componentName, out value);
        value = default;
        return false;
    }

    /// <summary>
    /// Resolves a borrow within <paramref name="reach"/>. Called by generated dispatch
    /// each tick rather than cached, so a borrow can never outlive the node it points
    /// at. An empty <paramref name="name"/> resolves by type alone.
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
        Entity    = 0;
    }

    /// <summary>Whether this node is bound to <paramref name="world"/> specifically.</summary>
    internal bool BelongsTo(ScriptHost world) => ReferenceEquals(ScriptHost, world);

    internal void BindToScene(ScriptHost scriptHost, ulong entity)
    {
        PreBind(scriptHost, entity);
        CompleteBind();
    }

    internal void PreBind(ScriptHost scriptHost, ulong entity)
    {
        ScriptHost = scriptHost;
        Entity    = entity;
    }

    /// <summary>
    /// Seeds one of this node's components at bind time: writes the value authored before
    /// binding, unless the entity already carries that component, in which case the
    /// existing value wins. That is what lets a node bind to an entity the native scene
    /// loader already populated without the managed defaults erasing what the scene
    /// authored — for every component alike, with no node type singled out.
    /// </summary>
    protected internal void GeneratedSeed<T>(uint cid, in T state) where T : unmanaged
    {
        if (ScriptHost!.TryGetByCid<T>(Entity, cid, out _)) return;
        ScriptHost.SetByCid(Entity, cid, in state);
    }

    /// <summary>
    /// Writes one of this node's component values. The generated property setters
    /// go through here rather than through the world itself, which is what lets
    /// the world stay private to <see cref="Node"/>: reaching a component is the
    /// only thing a node's own storage needs it for.
    /// </summary>
    protected internal void GeneratedSet<T>(uint cid, in T state) where T : unmanaged =>
        ScriptHost!.SetByCid(Entity, cid, in state);

    /// <summary>Reads one of this node's component values. Counterpart to <see cref="GeneratedSet{T}"/>.</summary>
    protected internal bool GeneratedTryGet<T>(uint cid, out T state) where T : unmanaged =>
        ScriptHost!.TryGetByCid(Entity, cid, out state);

    /// <summary>
    /// Reaches one of this node's components in place, so a generated property touches
    /// the one field it names instead of copying the whole struct in and back out.
    /// <paramref name="live"/> reports whether the returned reference is the component's
    /// own storage; when false it is <paramref name="authored"/>, the node's pre-bind
    /// value, and a writer must still publish through <see cref="GeneratedSet{T}"/> —
    /// which is the case both before binding and while an attach is queued behind a
    /// wave barrier.
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
    /// Hands this node one signal delivered to it, dispatching to the <c>On</c>
    /// method whose parameter type is <paramref name="payloadType"/>. Overridden by
    /// <c>NodePropertyGenerator</c> for node types that declare handlers; base is a
    /// no-op.
    /// </summary>
    /// <remarks>
    /// Signature-driven like the rest of the model: a node listens by declaring
    /// <c>void On(in TPayload e)</c>, so what it reacts to is readable from the
    /// method list rather than from a registration call somewhere else.
    /// </remarks>
    protected internal virtual void GeneratedDeliverSignal(Type payloadType, ReadOnlySpan<byte> payload) { }

    internal void CompleteBind()
    {
        GeneratedBind(ScriptHost!);
        OnBind(ScriptHost!);
    }
}
