namespace KernelEngine.Framework;

/// <summary>
/// A loaded 3D model: a list of <see cref="ModelMesh"/> entries (mesh + material pairs) plus the
/// <see cref="Texture"/>s referenced by the materials. Ref-counted as a single asset; releasing the
/// model releases every owned sub-resource. Create via <see cref="Assets"/>.
/// </summary>
public sealed class Model : Resource
{
    /// <summary>The sub-meshes that make up the model.</summary>
    public IReadOnlyList<ModelMesh> Meshes { get; }

    private readonly IReadOnlyList<Texture> _textures;
    private readonly IReadOnlyList<Material> _materials;

    internal Model(IReadOnlyList<ModelMesh> meshes, IReadOnlyList<Material> materials, IReadOnlyList<Texture> textures)
    {
        Meshes = meshes;
        _materials = materials;
        _textures = textures;
    }

    protected override void DestroyNative()
    {
        // Each ModelMesh entry holds its own reference to mesh + material (the material was
        // Retain'd at construction so a material shared across N entries is counted N times).
        // The materials list separately holds the +1 reference from creation.
        foreach (var entry in Meshes)
        {
            entry.Mesh.Release();
            entry.Material.Release();
        }
        foreach (var material in _materials) material.Release();
        foreach (var texture in _textures) texture.Release();
    }
}

/// <summary>A sub-mesh within a <see cref="Model"/>: a <see cref="Mesh"/> paired with its <see cref="Material"/>.</summary>
public sealed record ModelMesh(string Name, Mesh Mesh, Material Material);
