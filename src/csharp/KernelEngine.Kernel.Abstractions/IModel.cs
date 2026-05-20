namespace KernelEngine.Kernel;

/// <summary>
/// A model loaded by an <see cref="IAssetLoader"/>. Owns the decoded mesh, material,
/// and texture data. Disposing frees all underlying memory.
/// </summary>
public interface IModel : IDisposable
{
    /// <summary>All meshes in the model.</summary>
    IReadOnlyList<IModelMesh> Meshes { get; }

    /// <summary>All materials referenced by the meshes.</summary>
    IReadOnlyList<IModelMaterial> Materials { get; }

    /// <summary>All decoded textures referenced by the materials.</summary>
    IReadOnlyList<IModelTexture> Textures { get; }
}
