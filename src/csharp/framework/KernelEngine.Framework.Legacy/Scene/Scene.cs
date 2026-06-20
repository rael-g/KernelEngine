namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A reusable bundle of nodes: describe a subtree code-first via a builder action, then
/// <see cref="Instantiate"/> it into the live <see cref="Tree"/> as many times as you want.
/// Each call produces a fresh subtree rooted under its own parent node.
/// </summary>
/// <remarks>
/// Today: code-first only. Future: load from a serialized <c>.kescene</c> asset (Tier A asset
/// family), and inherit from other <see cref="Scene"/>s.
/// </remarks>
/// <example>
/// <code>
/// var enemy = new Scene((tree, root) => {
///     tree.AddNode(new MeshRenderer { Mesh = bodyMesh, Material = bodyMat }, "Body", parent: root);
///     tree.AddNode(new PointLight { Color = Vector3.UnitX, Intensity = 5f }, "Glow", parent: root);
/// }) { Name = "Enemy" };
///
/// enemy.Instantiate(app.Tree);
/// enemy.Instantiate(app.Tree).LocalTransform = ...;
/// </code>
/// </example>
public sealed class Scene
{
    private readonly Action<Tree, Node>? _build;

    /// <summary>Empty scene — its root is created but otherwise empty.</summary>
    public Scene() { }

    /// <summary>
    /// Scene whose subtree is constructed by <paramref name="build"/> each time it is instantiated.
    /// The builder receives the target <see cref="Tree"/> and the freshly created root node.
    /// </summary>
    public Scene(Action<Tree, Node> build) { _build = build; }

    /// <summary>Root node name used when instantiating (default: <c>"Scene"</c>).</summary>
    public string Name { get; init; } = "Scene";

    /// <summary>
    /// Adds a fresh instance of this scene to <paramref name="tree"/> under <paramref name="parent"/>
    /// (or the tree root when <c>null</c>) and returns the new root.
    /// </summary>
    public Node Instantiate(Tree tree, Node? parent = null)
    {
        var root = tree.AddNode(Name, parent);
        _build?.Invoke(tree, root);
        return root;
    }
}
