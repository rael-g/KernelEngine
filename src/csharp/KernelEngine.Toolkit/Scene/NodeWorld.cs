namespace KernelEngine.Framework;

/// <summary>
/// Node-aware facade over <see cref="World"/>. Lives in Toolkit (not Framework)
/// because Framework only knows ECS + Scene — it has no concept of <see cref="Node"/>.
/// Game code calls <see cref="AddNode{T}"/> to spawn entities and attach components;
/// every entity is created through the native <see cref="SceneTree"/> so hierarchy
/// and name are wired at the C level.
/// </summary>
public sealed class NodeWorld
{
    private readonly World               _world;
    private readonly IEcsAdapter         _ecs;
    private readonly IComponentRegistry  _components;

    private readonly List<Node>             _behaviors = new();
    private readonly List<Label>            _labels    = new();
    private readonly Dictionary<string, Node> _byName  = new(StringComparer.Ordinal);

    internal IReadOnlyList<Node>  Behaviors => _behaviors;
    internal IReadOnlyList<Label> Labels    => _labels;

    internal void RegisterBehavior(Node node) => _behaviors.Add(node);
    internal void RegisterLabel(Label label)  => _labels.Add(label);

    internal NodeWorld(World world, IEcsAdapter ecs, IComponentRegistry components)
    {
        _world      = world;
        _ecs        = ecs;
        _components = components;
    }

    /// <summary>
    /// Registers a node in the world: creates a native entity via the scene tree,
    /// binds the node to it, and lets the subclass materialize its components.
    /// </summary>
    public T AddNode<T>(T node, string name = "", Node? parent = null) where T : Node
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a world.");
        if (parent is not null && parent.NodeWorld != this)
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = _world.SceneTree.CreateNode(name, parent?.Entity ?? 0);
        node.Name  = name;
        node.BindToNodeWorld(this, entity);
        parent?.AttachChild(node);
        if (!string.IsNullOrEmpty(name)) _byName[name] = node;
        return node;
    }

    /// <summary>
    /// First phase used by the scene loader: assigns entity + name + parent,
    /// but does NOT yet invoke the subclass's OnBind. The loader applies
    /// component data then calls <see cref="CompleteAddNode"/>.
    /// </summary>
    internal void PreAddNode(Node node, string name, Node? parent)
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a world.");
        if (parent is not null && parent.NodeWorld != this)
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different world.");

        var entity = _world.SceneTree.CreateNode(name, parent?.Entity ?? 0);
        node.Name  = name;
        node.PreBind(this, entity);
        parent?.AttachChild(node);
        if (!string.IsNullOrEmpty(name)) _byName[name] = node;
    }

    internal void CompleteAddNode(Node node) => node.CompleteBind();

    /// <summary>Finds a node by its exact name.</summary>
    public Node? Find(string name) => _byName.TryGetValue(name, out var n) ? n : null;

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
    /// Removes <paramref name="node"/> from the world, destroys its native entity,
    /// and clears its binding. Idempotent on unbound nodes.
    /// </summary>
    public void DestroyNode(Node node)
    {
        if (!node.IsBound || node.NodeWorld != this) return;
        if (!string.IsNullOrEmpty(node.Name)) _byName.Remove(node.Name);
        var kids = node.Children.ToArray();
        for (int i = 0; i < kids.Length; i++) DestroyNode(kids[i]);

        node.Parent?.DetachChild(node);
        node.OnUnbind();

        if (node.HasBehavior)  _behaviors.Remove(node);
        if (node is Label l)   _labels.Remove(l);
        _world.SceneTree.DestroyNode(node.Entity);
        node.UnbindFromNodeWorld();
    }

    /// <summary>
    /// Destroys every node currently in the world. Used by <see cref="SceneRouter"/>
    /// to flush a scene before loading the next one.
    /// </summary>
    public void Clear()
    {
        var roots = _byName.Values.Where(n => n.Parent is null).ToArray();
        for (int i = 0; i < roots.Length; i++) DestroyNode(roots[i]);
    }

    // ── Generic component access ──────────────────────────────────────────────

    internal void Set<T>(ulong entity, in T value) where T : unmanaged
        => _ecs.Add(entity, _components.CidOf<T>(), value);

    internal bool TryGet<T>(ulong entity, out T value) where T : unmanaged
        => _ecs.TryGet(entity, _components.CidOf<T>(), out value);
}
