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
    /// Optional parent node — set when this node was added via
    /// <see cref="Framework.Tree.AddNode{T}(T, string, Node?)"/> with a non-null
    /// parent. Null for top-level nodes. The relationship is purely structural
    /// today (for scene-file <c>parent = "X"</c> grouping and path lookup);
    /// world-transform cascading is a future addition.
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

    // ── Transform (always present on every node) ────────────────────────────
    //
    // Backing field is used pre-bind. After bind, the setter writes through to
    // the ECS TransformComponent (so per-frame mutation by game scripts lands
    // in the same data the render systems query).

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

    // ── Lifecycle hooks ─────────────────────────────────────────────────────

    /// <summary>
    /// Called once by <see cref="Tree.AddNode"/> after the entity has been
    /// created. Subclasses materialize their components here from the init
    /// properties the game code set via object-initializer syntax.
    /// </summary>
    protected internal abstract void OnBind(Tree tree);

    /// <summary>
    /// Called every simulation tick on bound nodes. Default is a no-op so
    /// only nodes that need per-frame logic pay the virtual-call cost
    /// (BehaviorSystem skips nodes whose OnUpdate is the base method via the
    /// <see cref="HasBehavior"/> flag computed at first bind).
    /// </summary>
    /// <remarks>
    /// Mutating state through <see cref="View"/> or this node's own properties
    /// is the only sanctioned way to drive simulation. Reaching into ECS
    /// internals or calling native APIs from inside this method violates the
    /// script-safety doctrine (the analyzer enforces the static rules; the
    /// View funnel enforces the runtime ones).
    /// </remarks>
    protected internal virtual void OnUpdate(in View view) { }

    /// <summary>
    /// Called once when the node is being removed from the tree (manual
    /// <see cref="Framework.Tree.DestroyNode"/> or scene swap). Scripts that
    /// own external resources (physics bodies, audio voices, GPU handles
    /// they created themselves) release them here. The base implementation
    /// is a no-op.
    /// </summary>
    protected internal virtual void OnUnbind() { }

    /// <summary>
    /// True if the subclass overrode <see cref="OnUpdate"/>. Computed once at
    /// bind so BehaviorSystem can iterate only the entities that actually have
    /// per-frame logic instead of every node in the tree.
    /// </summary>
    internal bool HasBehavior { get; private set; }

    /// <summary>
    /// Clears the binding so the node can no longer reach the tree. Called by
    /// <see cref="Framework.Tree.DestroyNode"/>; not part of the public API.
    /// </summary>
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

    /// <summary>
    /// First phase of binding: assigns the tree + entity + pre-bind transform.
    /// Used by the <see cref="Framework.SceneLoader"/> so it can apply scene
    /// properties (which may overwrite the pre-bind transform) BEFORE the
    /// subclass's <see cref="OnBind"/> runs and reads the final state.
    /// </summary>
    internal void PreBind(Tree tree, ulong entity)
    {
        Tree   = tree;
        Entity = entity;
        tree.Set(entity, _transform);
    }

    /// <summary>
    /// Second phase of binding: re-syncs the (possibly mutated) transform,
    /// calls the subclass's <see cref="OnBind"/>, then detects the behavior
    /// override + registers the node with the tree's per-tick walks.
    /// </summary>
    internal void CompleteBind()
    {
        // Properties applied between PreBind and here may have mutated _transform;
        // re-sync so OnBind reads the final pose.
        Tree!.Set(Entity, _transform);
        OnBind(Tree);

        var m = GetType().GetMethod(nameof(OnUpdate),
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public);
        HasBehavior = m != null && m.DeclaringType != typeof(Node);

        if (HasBehavior) Tree!.RegisterBehavior(this);
    }
}
