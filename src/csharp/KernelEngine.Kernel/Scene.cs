namespace KernelEngine.Kernel;

/// <summary>
/// Thin facade over the world's ECS node management.
/// Non-owning view: the <see cref="World"/> controls node lifetime.
/// </summary>
public sealed class Scene
{
    private readonly World _world;
    private Node? _root;

    internal Scene(World world) => _world = world;

    /// <summary>The implicit root node of this scene (entity 1).</summary>
    public Node Root => _root ??= new Node(_world.GetRoot(), _world, "Root");

    // ── High-level add ────────────────────────────────────────────────────────

    /// <summary>
    /// Creates a plain (non-scripted) node and adds it as a child of
    /// <paramref name="parent"/> (defaults to <see cref="Root"/>).
    /// </summary>
    public Node AddNode(string name, Node? parent = null)
    {
        var parentEntity = parent?.Entity ?? Root.Entity;
        var entity = _world.CreateNode(name, parentEntity);
        return new Node(entity, _world, name);
    }

    /// <summary>
    /// Creates a scripted node and adds it as a child of <paramref name="parent"/>
    /// (defaults to <see cref="Root"/>). The node's <see cref="Node.OnStart"/> and
    /// <see cref="Node.OnUpdate"/> overrides will be called by the ScriptSystem.
    /// </summary>
    public T AddNode<T>(T node, string name, Node? parent = null) where T : Node
    {
        var parentEntity = parent?.Entity ?? Root.Entity;
        var entity = _world.CreateNode(name, parentEntity);
        node.Initialize(entity, _world, name);
        node.RegisterScript();
        return node;
    }

    // ── Destruction ───────────────────────────────────────────────────────────

    /// <summary>
    /// Destroys a node (and its descendants) and removes it from the scripting registry.
    /// Do not use <paramref name="node"/> after this call.
    /// </summary>
    public void DestroyNode(Node node)
    {
        Node.Unregister(node.Entity);
        _world.DestroyNode(node.Entity);
    }
}
