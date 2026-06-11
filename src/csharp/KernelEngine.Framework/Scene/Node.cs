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

    // ── Transform (always present on every node) ────────────────────────────
    //
    // Backing field is used pre-bind. After bind, the setter writes through to
    // the ECS TransformComponent (so per-frame mutation by game scripts lands
    // in the same data the render systems query).

    private TransformComponent _transform = TransformComponent.Identity;

    public TransformComponent LocalTransform
    {
        get => IsBound ? Tree!.GetTransform(Entity) : _transform;
        set
        {
            _transform = value;
            if (IsBound) Tree!.SetTransform(Entity, value);
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
    /// True if the subclass overrode <see cref="OnUpdate"/>. Computed once at
    /// bind so BehaviorSystem can iterate only the entities that actually have
    /// per-frame logic instead of every node in the tree.
    /// </summary>
    internal bool HasBehavior { get; private set; }

    internal void BindToTree(Tree tree, ulong entity)
    {
        Tree   = tree;
        Entity = entity;
        // Sync the pre-bind transform into the ECS before subclass hooks.
        tree.SetTransform(entity, _transform);
        OnBind(tree);

        // Reflection allowed only at bind time (engine-side, not script-side)
        // to detect override once and cache the flag.
        var m = GetType().GetMethod(nameof(OnUpdate),
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public);
        HasBehavior = m != null && m.DeclaringType != typeof(Node);

        if (HasBehavior) tree.RegisterBehavior(this);
    }
}
