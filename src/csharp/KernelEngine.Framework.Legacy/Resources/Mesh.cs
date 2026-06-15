using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A ref-counted GPU mesh. Create via <see cref="ResourceManager"/>; assign to a mesh node instead
/// of juggling a raw <see cref="MeshHandle"/>.
/// </summary>
public sealed class Mesh : Resource
{
    /// <summary>The underlying GPU handle (engine-internal — read by render systems).</summary>
    internal MeshHandle Handle { get; }

    internal Mesh(IResourceCacheBackend cache, MeshHandle handle) : base(cache, handle.Value)
    {
        Handle = handle;
    }
}
