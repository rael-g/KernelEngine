namespace KernelEngine.Framework;

/// <summary>
/// Base class for game-facing scene objects. A Node is the managed wrapper
/// around an ECS entity. Game code instantiates subclasses with init properties
/// (object-initializer syntax) and hands them to <see cref="Tree.AddNode"/>;
/// AddNode creates the entity and asks the node to materialize its components.
/// </summary>
public abstract class Node
{
    /// <summary>ECS entity this node wraps. 0 before AddNode.</summary>
    public ulong Entity { get; private set; }

    /// <summary>The tree that owns this node. Null before AddNode.</summary>
    public Tree? Tree { get; private set; }

    /// <summary>Display name (debug / lookups). Set by AddNode from its name parameter.</summary>
    public string Name { get; internal set; } = "";

    /// <summary>True after AddNode binds this node to an entity.</summary>
    public bool IsBound => Tree != null;

    /// <summary>
    /// Optional parent node. Set when this node was added via
    /// <see cref="Framework.Tree.AddNode{T}(T, string, Node?)"/> with a non-null parent.
    /// </summary>
    public Node? Parent { get; private set; }

    private readonly List<Node> _children = new();
    public IReadOnlyList<Node> Children => _children;

    internal void AttachChild(Node child)
    {
        child.Parent = this;
        _children.Add(child);
    }

    internal void DetachChild(Node child)
    {
        child.Parent = null;
        _children.Remove(child);
    }

    // ── Transform ────────────────────────────────────────────────────────────

    private TransformComponent _transform = TransformComponent.Identity;

    public TransformComponent LocalTransform
    {
        get
        {
            if (!IsBound) return _transform;
            return Tree!.TryGet<TransformComponent>(Entity, out var v) ? v : TransformComponent.Identity;
        }
        set
        {
            _transform = value;
            if (IsBound) Tree!.Set(Entity, value);
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /// <summary>
    /// Called once by <see cref="Tree.AddNode"/> after the entity has been
    /// created. Subclasses materialize their ECS components here from the
    /// properties the game code set via object-initializer syntax.
    /// </summary>
    protected internal abstract void OnBind(Tree tree);

    /// <summary>
    /// Called every simulation tick on bound nodes. Default is a no-op so
    /// only nodes that override this pay the virtual-call cost each frame.
    /// </summary>
    protected internal virtual void OnUpdate(in View view) { }

    /// <summary>
    /// Called once when the node is removed from the tree. Scripts that own
    /// external resources release them here. Base implementation is a no-op.
    /// </summary>
    protected internal virtual void OnUnbind() { }

    /// <summary>
    /// True if the subclass overrode <see cref="OnUpdate"/>. Computed once at
    /// bind so BehaviorSystem iterates only the nodes that have per-frame logic.
    /// </summary>
    internal bool HasBehavior { get; private set; }

    internal void UnbindFromTree()
    {
        Tree   = null;
        Entity = 0;
    }

    internal void BindToTree(Tree tree, ulong entity)
    {
        PreBind(tree, entity);
        CompleteBind();
    }

    internal void PreBind(Tree tree, ulong entity)
    {
        Tree   = tree;
        Entity = entity;
        tree.Set(entity, _transform);
    }

    internal void CompleteBind()
    {
        Tree!.Set(Entity, _transform);
        OnBind(Tree);

        var m = GetType().GetMethod(nameof(OnUpdate),
            System.Reflection.BindingFlags.Instance |
            System.Reflection.BindingFlags.NonPublic |
            System.Reflection.BindingFlags.Public);
        HasBehavior = m != null && m.DeclaringType != typeof(Node);

        if (HasBehavior) Tree!.RegisterBehavior(this);
    }
}
