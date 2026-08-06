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
    /// created. Subclasses materialize their ECS components here from the
    /// properties the game code set via object-initializer syntax.
    /// </summary>
    protected internal abstract void OnBind(NodeWorld nodeWorld);

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

    internal void CompleteBind()
    {
        OnBind(NodeWorld!);
        if (HasBehavior) NodeWorld!.RegisterBehavior(this);
    }
}
