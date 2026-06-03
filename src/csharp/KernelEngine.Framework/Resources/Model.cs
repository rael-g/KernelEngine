namespace KernelEngine.Framework;

/// <summary>
/// A loaded 3D model: a list of <see cref="ModelMesh"/> entries (mesh + material pairs) plus the
/// <see cref="Texture"/>s referenced by the materials. Ref-counted via the native resource cache
/// using a synthetic handle; releasing the model releases every owned sub-resource. Create via
/// <see cref="Assets"/>.
/// </summary>
public sealed class Model : Resource
{
    /// <summary>The sub-meshes that make up the model.</summary>
    public IReadOnlyList<ModelMesh> Meshes { get; }

    internal Model(NativeResourceCache cache,
                   uint                syntheticHandle,
                   IReadOnlyList<ModelMesh> meshes) : base(cache, syntheticHandle)
    {
        Meshes = meshes;
    }
}

/// <summary>A sub-mesh within a <see cref="Model"/>: a <see cref="Mesh"/> paired with its <see cref="Material"/>.</summary>
public sealed record ModelMesh(string Name, Mesh Mesh, Material Material);
