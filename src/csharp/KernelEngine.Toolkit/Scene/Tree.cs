using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Scene-graph facade. Game code uses <see cref="AddNode{T}"/> to spawn
/// entities and attach components. Under the hood every node is an ECS entity;
/// the Tree packages spawn + component setup + naming behind one call.
/// </summary>
public sealed class Tree
{
    internal IEcsAdapter        Ecs        { get; }
    internal IComponentRegistry Components { get; }

    // Bound nodes that overrode OnUpdate. BehaviorSystem iterates this list
    // each tick. Built during AddNode and never written from the tick path.
    private readonly List<Node> _behaviors = new();
    internal IReadOnlyList<Node> Behaviors => _behaviors;
    internal void RegisterBehavior(Node node) => _behaviors.Add(node);

    // Labels live outside ECS (managed references). Populated during scene
    // setup, iterated by LabelContributor every frame.
    private readonly List<Label> _labels = new();
    internal IReadOnlyList<Label> Labels => _labels;
    internal void RegisterLabel(Label label) => _labels.Add(label);

    /// <summary>
    /// Direct access to the renderer for creating GPU resources (textures,
    /// materials, meshes). Setup callbacks run on the render worker.
    /// </summary>
    public IRenderer Renderer { get; }

    internal Tree(IEcsAdapter ecs, IComponentRegistry components, IRenderer renderer)
    {
        Ecs        = ecs;
        Components = components;
        Renderer   = renderer;
    }

    private readonly Dictionary<string, Node> _byName = new(StringComparer.Ordinal);

    /// <summary>
    /// Registers a node in the tree: creates an entity, binds the node to it,
    /// and lets the subclass materialize its components.
    /// </summary>
    public T AddNode<T>(T node, string name = "", Node? parent = null) where T : Node
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a tree.");
        if (parent is not null && parent.Tree != this)
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different tree.");

        var entity = Ecs.CreateEntity();
        node.Name = name;
        node.BindToTree(this, entity);
        parent?.AttachChild(node);
        if (!string.IsNullOrEmpty(name)) _byName[name] = node;
        return node;
    }

    /// <summary>
    /// First phase used by <see cref="SceneLoader"/>: assigns entity + name + parent,
    /// but does NOT yet invoke the subclass's OnBind. The loader applies scene-file
    /// properties then calls <see cref="CompleteAddNode"/>.
    /// </summary>
    internal void PreAddNode(Node node, string name, Node? parent)
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a tree.");
        if (parent is not null && parent.Tree != this)
            throw new InvalidOperationException(
                $"Cannot attach '{name}' to parent '{parent.Name}' — parent belongs to a different tree.");

        var entity = Ecs.CreateEntity();
        node.Name = name;
        node.PreBind(this, entity);
        parent?.AttachChild(node);
        if (!string.IsNullOrEmpty(name)) _byName[name] = node;
    }

    internal void CompleteAddNode(Node node) => node.CompleteBind();

    public Node? Find(string name) => _byName.TryGetValue(name, out var n) ? n : null;

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
    /// Removes <paramref name="node"/> from the tree, destroys its ECS entity,
    /// and clears its binding. Idempotent on unbound nodes.
    /// </summary>
    public void DestroyNode(Node node)
    {
        if (!node.IsBound || node.Tree != this) return;
        if (!string.IsNullOrEmpty(node.Name)) _byName.Remove(node.Name);
        var kids = node.Children.ToArray();
        for (int i = 0; i < kids.Length; i++) DestroyNode(kids[i]);

        node.Parent?.DetachChild(node);
        node.OnUnbind();

        if (node.HasBehavior) _behaviors.Remove(node);
        if (node is Label l)  _labels.Remove(l);
        Ecs.EntityDestroy(node.Entity);
        node.UnbindFromTree();
    }

    /// <summary>
    /// Destroys every node currently in the tree. Used by <see cref="SceneRouter"/>
    /// to flush a scene before loading the next one.
    /// </summary>
    public void Clear()
    {
        var roots = _byName.Values.Where(n => n.Parent is null).ToArray();
        for (int i = 0; i < roots.Length; i++) DestroyNode(roots[i]);
    }

    // ── Generic component access ──────────────────────────────────────────────

    internal void Set<T>(ulong entity, in T value) where T : unmanaged
        => Ecs.Add(entity, Components.CidOf<T>(), value);

    internal bool TryGet<T>(ulong entity, out T value) where T : unmanaged
        => Ecs.TryGet(entity, Components.CidOf<T>(), out value);
}
