namespace KernelEngine.Framework;

/// <summary>
/// High-level helpers over <see cref="Scene"/> that work with managed resources/aggregates
/// (e.g. <see cref="Model"/>), so game code doesn't write the texture→material→mesh upload loop.
/// </summary>
public static class SceneExtensions
{
    /// <summary>
    /// Adds <paramref name="model"/>'s meshes to the scene under a new parent node. Each
    /// sub-mesh becomes a <see cref="MeshRenderer"/> (which retains its <see cref="Mesh"/> +
    /// <see cref="Material"/>). The returned root is the parent — transform it to place/scale
    /// the whole model.
    /// </summary>
    /// <param name="scene">The scene to add into.</param>
    /// <param name="model">The model (typically from <see cref="Assets.LoadModelAsync"/>).</param>
    /// <param name="name">Name for the root node (default: "Model").</param>
    /// <param name="parent">Optional parent for the model root.</param>
    public static Node Add(this Scene scene, Model model, string name = "Model", Node? parent = null)
    {
        var root = scene.AddNode(name, parent);
        foreach (var entry in model.Meshes)
        {
            scene.AddNode(
                new MeshRenderer { Mesh = entry.Mesh, Material = entry.Material },
                entry.Name,
                parent: root);
        }
        return root;
    }
}
