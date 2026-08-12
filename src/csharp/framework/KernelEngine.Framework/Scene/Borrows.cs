namespace KernelEngine.Framework;

/// <summary>
/// Names the node a borrow parameter resolves to when the parameter's own name is
/// not the node's name. Without it a borrow binds to the child, descendant, or
/// ancestor whose name matches the parameter.
/// </summary>
[AttributeUsage(AttributeTargets.Parameter)]
public sealed class NodeNameAttribute : Attribute
{
    /// <summary>The scene name of the node this parameter borrows.</summary>
    public string Name { get; }

    /// <param name="name">The scene name of the node this parameter borrows.</param>
    public NodeNameAttribute(string name) => Name = name;
}

/// <summary>
/// A borrow of a child node of type <typeparamref name="T"/>, obtained as a
/// parameter rather than stored in a field. Re-resolved each tick, so it can never
/// dangle, and its type is what puts <typeparamref name="T"/>'s components into the
/// borrowing system's access list.
/// </summary>
public readonly ref struct Child<T> where T : Node
{
    private readonly T? _node;

    /// <summary>The borrowed node, or null when no matching child is bound.</summary>
    public T? Node => _node;

    /// <summary>True when a matching child was found this tick.</summary>
    public bool IsBound => _node is not null;

    internal Child(T? node) => _node = node;

    /// <summary>Unwraps the borrow, throwing when no matching child is bound.</summary>
    public T Value => _node ?? throw new InvalidOperationException(
        $"No child of type {typeof(T).Name} is bound for this borrow.");
}

/// <summary>
/// A borrow of a node anywhere in the tree, matched by name. Unlike
/// <see cref="Child{T}"/> it does not require a parent relationship, which is what
/// a node reporting to a sibling subsystem needs.
/// </summary>
public readonly ref struct Ref<T> where T : Node
{
    private readonly T? _node;

    /// <summary>The borrowed node, or null when no matching node is bound.</summary>
    public T? Node => _node;

    /// <summary>True when a matching node was found this tick.</summary>
    public bool IsBound => _node is not null;

    internal Ref(T? node) => _node = node;

    /// <summary>Unwraps the borrow, throwing when no matching node is bound.</summary>
    public T Value => _node ?? throw new InvalidOperationException(
        $"No node of type {typeof(T).Name} is bound for this borrow.");
}

/// <summary>A borrow of the nearest ancestor of type <typeparamref name="T"/>.</summary>
public readonly ref struct Parent<T> where T : Node
{
    private readonly T? _node;

    /// <summary>The borrowed node, or null when no matching ancestor is bound.</summary>
    public T? Node => _node;

    /// <summary>True when a matching ancestor was found this tick.</summary>
    public bool IsBound => _node is not null;

    internal Parent(T? node) => _node = node;

    /// <summary>Unwraps the borrow, throwing when no matching ancestor is bound.</summary>
    public T Value => _node ?? throw new InvalidOperationException(
        $"No ancestor of type {typeof(T).Name} is bound for this borrow.");
}
