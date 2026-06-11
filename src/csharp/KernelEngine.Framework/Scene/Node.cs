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

    internal void BindToTree(Tree tree, ulong entity)
    {
        Tree   = tree;
        Entity = entity;
        // Sync the pre-bind transform into the ECS before subclass hooks.
        tree.SetTransform(entity, _transform);
        OnBind(tree);
    }
}
