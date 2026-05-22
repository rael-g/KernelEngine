using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A ref-counted GPU mesh. Create via <see cref="ResourceManager"/>; assign to a mesh node instead
/// of juggling a raw <see cref="MeshHandle"/>.
/// </summary>
public sealed class Mesh : Resource
{
    private readonly IResourceFactory _factory;

    /// <summary>The underlying GPU handle (engine-internal — read by render systems).</summary>
    internal MeshHandle Handle { get; }

    internal Mesh(IResourceFactory factory, MeshHandle handle)
    {
        _factory = factory;
        Handle = handle;
    }

    protected override void DestroyNative() => _factory.DestroyMesh(Handle);
}
