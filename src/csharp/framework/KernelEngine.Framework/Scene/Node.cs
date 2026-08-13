using KernelEngine.Ecs;


namespace KernelEngine.Framework;

/// <summary>
/// Base class for game-facing scene objects. A Node is the managed wrapper
/// around an ECS entity. Game code instantiates subclasses with init properties
/// (object-initializer syntax) and hands them to <see cref="NodeWorld.AddNode"/>;
/// AddNode creates the native entity and asks the node to materialize its components.
/// </summary>
public abstract class Node
{
    /// <summary>ECS entity this node wraps. 0 before AddNode.</summary>
    public ulong Entity { get; private set; }

    /// <summary>The world that owns this node. Null before AddNode.</summary>
    public NodeWorld? NodeWorld { get; private set; }

    /// <summary>
    /// Display name (debug / lookups). Read live from <c>ke_name_component</c> —
    /// not a managed copy, so it can never drift from the entity's actual name.
    /// "" before AddNode binds this node.
    /// </summary>
    public string Name => NodeWorld?.GetName(Entity) ?? "";

    /// <summary>True after AddNode binds this node to an entity.</summary>
    public bool IsBound => NodeWorld != null;

    /// <summary>
    /// Parent node, resolved live from <c>ke_hierarchy_component</c>. Null before
    /// binding, when this node has no parent, or when the parent entity has no
    /// managed <see cref="Framework.Node"/> bound to it.
    /// </summary>
    public Node? Parent => NodeWorld?.GetParent(Entity);

    /// <summary>
    /// Child nodes, walked live from <c>ke_hierarchy_component</c> in insertion
    /// order. Empty before binding.
    /// </summary>
    public IReadOnlyList<Node> Children => NodeWorld?.GetChildren(Entity) ?? Array.Empty<Node>();

    /// <summary>
    /// Called once by <see cref="NodeWorld.AddNode"/> after the entity has been
    /// created and after <see cref="GeneratedBind"/> has materialized this node's
    /// generated components. Override to materialize components the generator does
    /// not know about. Base implementation is a no-op.
    /// </summary>
    protected internal virtual void OnBind(NodeWorld nodeWorld) { }

    /// <summary>
    /// Materializes the components this node's generated properties are backed by:
    /// resolves each component id and seeds the values authored before binding.
    /// Overridden by <c>NodePropertyGenerator</c>; base is a no-op.
    /// </summary>
    /// <remarks>
    /// Separate from <see cref="OnBind"/> so the generator and the node's own author
    /// are never competing for the same method — a node that needs both keeps both.
    /// </remarks>
    protected internal virtual void GeneratedBind(NodeWorld nodeWorld) { }

    /// <summary>
    /// Called once after all entities in the scene are loaded and all
    /// <c>[entity.properties]</c> blocks have been applied. Override to read
    /// scene-file properties or look up sibling nodes (via <see cref="NodeWorld.Find"/>)
    /// that are guaranteed to exist at this point.
    /// Base implementation is a no-op.
    /// </summary>
    protected internal virtual void OnReady() { }

    /// <summary>
    /// Reads the <c>[entity.properties]</c> block declared in the scene file
    /// for this node. Returns false when no properties block was declared.
    /// Only valid during or after <see cref="OnReady"/>.
    /// </summary>
    protected bool TryGetProperties(out VariantReader reader)
    {
        if (NodeWorld is null) { reader = default; return false; }
        return NodeWorld.TryGetProperties(Entity, out reader);
    }

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
    /// override never enters <see cref="Framework.NodeWorld.Behaviors"/>.
    /// </summary>
    protected internal virtual bool HasBehavior => false;

    /// <summary>
    /// Appends the ECS component names this node type reaches, so the scheduler can
    /// order its behavior against every other writer of those components instead of
    /// trusting phase placement. An override calls the base first and then adds its
    /// own, which is what makes an inherited component set accumulate down the chain.
    /// </summary>
    protected internal virtual void CollectBehaviorComponents(List<string> into) { }

    /// <summary>
    /// Resolves a <see cref="Child{T}"/> borrow by node name. Called by generated
    /// dispatch each tick rather than cached, so a borrow can never outlive the node
    /// it points at.
    /// </summary>
    protected internal Child<T> BorrowChild<T>(string name) where T : Node
    {
        foreach (var child in Children)
            if (child is T typed && child.Name == name) return new Child<T>(typed);
        NodeWorld?.ReportUnresolvedBorrow(this, "Child", typeof(T).Name, name);
        return default;
    }

    /// <summary>
    /// Resolves an <see cref="Emit{T}"/> borrow: the right to raise signal
    /// <typeparamref name="T"/> from this node.
    /// </summary>
    protected internal Emit<T> BorrowEmit<T>() where T : unmanaged =>
        NodeWorld is null ? default : NodeWorld.EmitFor<T>(Entity);

    /// <summary>Resolves a <see cref="Ref{T}"/> borrow by node name, anywhere in the tree.</summary>
    protected internal Ref<T> BorrowRef<T>(string name) where T : Node
    {
        if (NodeWorld?.Find(name) is T typed) return new Ref<T>(typed);
        NodeWorld?.ReportUnresolvedBorrow(this, "Ref", typeof(T).Name, name);
        return default;
    }

    /// <summary>Resolves a <see cref="Parent{T}"/> borrow to the nearest matching ancestor.</summary>
    protected internal Parent<T> BorrowParent<T>(string name) where T : Node
    {
        for (var p = Parent; p is not null; p = p.Parent)
            if (p is T typed && (name.Length == 0 || p.Name == name)) return new Parent<T>(typed);
        NodeWorld?.ReportUnresolvedBorrow(this, "Parent", typeof(T).Name, name);
        return default;
    }

    internal void UnbindFromNodeWorld()
    {
        NodeWorld = null;
        Entity    = 0;
    }

    internal void BindToNodeWorld(NodeWorld nodeWorld, ulong entity)
    {
        PreBind(nodeWorld, entity);
        CompleteBind();
    }

    internal void PreBind(NodeWorld nodeWorld, ulong entity)
    {
        NodeWorld = nodeWorld;
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
        if (NodeWorld!.TryGetByCid<T>(Entity, cid, out _)) return;
        NodeWorld.SetByCid(Entity, cid, in state);
    }

    /// <summary>
    /// Applies this node's <c>[entity.properties]</c> block onto its generated
    /// properties, after <see cref="OnBind"/> has seeded their defaults and before
    /// <see cref="OnReady"/> runs. Overridden by <c>NodePropertyGenerator</c> for
    /// node types that declare properties; base is a no-op, so a hand-written node
    /// keeps reading the bag itself.
    /// </summary>
    /// <remarks>
    /// Seeding first and authoring on top is what makes a field the scene omits keep
    /// the node's own default instead of falling to zero.
    /// </remarks>
    protected internal virtual void GeneratedApplyProperties() { }

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
        GeneratedBind(NodeWorld!);
        OnBind(NodeWorld!);
        if (HasBehavior) NodeWorld!.RegisterBehavior(this);
    }
}
