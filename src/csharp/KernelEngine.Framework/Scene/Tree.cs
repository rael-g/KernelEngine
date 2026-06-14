using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Scene-graph facade matching the legacy Tree API. Game code uses
/// <see cref="AddNode{T}"/> to spawn entities + attach the node's components.
/// Under the hood, every node is an entity in the runtime's flecs world; the
/// Tree just packages spawn + component setup + naming behind one call.
/// </summary>
public sealed class Tree
{
    internal EcsAdapter        Ecs        { get; }
    internal ComponentRegistry Components { get; }

    // Bound nodes that overrode OnUpdate. BehaviorSystem iterates this list
    // each tick. Built during Tree.AddNode and never written from the tick
    // path (no spawning from inside OnUpdate yet).
    private readonly List<Node> _behaviors = new();
    internal IReadOnlyList<Node> Behaviors => _behaviors;
    internal void RegisterBehavior(Node node) => _behaviors.Add(node);

    // Labels live outside ECS because they carry managed references (Font,
    // Text) that can't sit in unmanaged storage. Same registration shape as
    // behaviors — populated during scene setup, iterated by LabelContributor
    // every frame.
    private readonly List<Label> _labels = new();
    internal IReadOnlyList<Label> Labels => _labels;
    internal void RegisterLabel(Label label) => _labels.Add(label);

    /// <summary>
    /// Direct access to the renderer for creating GPU resources (textures,
    /// materials, meshes). Setup callbacks run on the render worker, so calls
    /// to <c>tree.Renderer.CreateTexture</c> etc. are safe with respect to
    /// bgfx's thread affinity.
    /// </summary>
    public IRenderer Renderer { get; }

    /// <summary>The native world aggregator that owns this tree's ECS and runtime.</summary>
    public World World { get; }

    internal unsafe Tree(World world, ComponentRegistry components, IRenderer renderer)
    {
        World      = world;
        Ecs        = new EcsAdapter(world.Ecs);
        Components = components;
        Renderer   = renderer;
    }

    /// <summary>
    /// Registers a node in the tree: creates an entity, binds the node to it,
    /// and lets the subclass materialize its components.
    /// </summary>
    private readonly Dictionary<string, Node> _byName = new(StringComparer.Ordinal);

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
    /// First phase used by <see cref="SceneLoader"/>: assigns the entity +
    /// name + parent slot, but does NOT yet invoke the subclass's OnBind.
    /// The loader then applies scene-file properties and finishes binding via
    /// <see cref="CompleteAddNode"/>.
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

    /// <summary>
    /// Finds a node by its name. First-match wins when multiple nodes share a
    /// name — game code that relies on Find should keep names unique. Returns
    /// null when no match exists; the typed overload throws if the type
    /// doesn't match so the caller gets a clear failure at the first read.
    /// </summary>
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
    /// Removes <paramref name="node"/> from the tree: detaches behaviors + labels
    /// from the per-tick walks, deletes the ECS entity (which drops every
    /// component attached to it), and clears the node's binding so it can't be
    /// re-added accidentally. Idempotent on unbound nodes.
    /// </summary>
    public void DestroyNode(Node node)
    {
        if (!node.IsBound || node.Tree != this) return;
        if (!string.IsNullOrEmpty(node.Name)) _byName.Remove(node.Name);
        // Walk children first so the whole subtree leaves the tree atomically.
        // Snapshot the list because DestroyNode mutates _children via DetachChild.
        var kids = node.Children.ToArray();
        for (int i = 0; i < kids.Length; i++) DestroyNode(kids[i]);

        node.Parent?.DetachChild(node);

        node.OnUnbind();  // script-owned resource cleanup (physics bodies, etc.)

        if (node.HasBehavior) _behaviors.Remove(node);
        if (node is Label l)  _labels.Remove(l);
        Ecs.EntityDestroy(node.Entity);
        node.UnbindFromTree();
    }

    /// <summary>
    /// Destroys every node currently in the tree, in reverse-of-add order.
    /// Used by <see cref="ISceneRouter"/> to flush a scene before loading the
    /// next one.
    /// </summary>
    public void Clear()
    {
        // Snapshot top-level nodes (parent == null); DestroyNode recurses
        // into children, so iterating roots is enough.
        var roots = _byName.Values.Where(n => n.Parent is null).ToArray();
        for (int i = 0; i < roots.Length; i++) DestroyNode(roots[i]);
    }

    // ── Generic component access ────────────────────────────────────────────
    //
    // Tree knows about entities + ECS plumbing; it does NOT know about each
    // specific component type. Node subclasses call Set<T>/TryGet<T> with the
    // component struct they own, and the cid is looked up once via the
    // ComponentRegistry. Adding a new component type means adding a struct +
    // registering it in ComponentRegistry — no edits to Tree.

    internal void Set<T>(ulong entity, in T value) where T : unmanaged
        => Ecs.Add(entity, Components.CidOf<T>(), value);

    internal bool TryGet<T>(ulong entity, out T value) where T : unmanaged
        => Ecs.TryGet(entity, Components.CidOf<T>(), out value);
}
