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

    internal Tree(EcsAdapter ecs, ComponentRegistry components, IRenderer renderer)
    {
        Ecs        = ecs;
        Components = components;
        Renderer   = renderer;
    }

    /// <summary>
    /// Registers a node in the tree: creates an entity, binds the node to it,
    /// and lets the subclass materialize its components.
    /// </summary>
    public T AddNode<T>(T node, string name = "") where T : Node
    {
        if (node.IsBound)
            throw new InvalidOperationException($"Node '{node.Name}' is already added to a tree.");
        var entity = Ecs.CreateEntity();
        node.Name = name;
        node.BindToTree(this, entity);
        return node;
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
        if (node.HasBehavior) _behaviors.Remove(node);
        if (node is Label l)  _labels.Remove(l);
        Ecs.EntityDestroy(node.Entity);
        node.UnbindFromTree();
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
