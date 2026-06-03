using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A ref-counted GPU material. Create via <see cref="ResourceManager"/>; assign to a mesh node
/// instead of juggling a raw <see cref="MaterialHandle"/>.
/// </summary>
public sealed class Material : Resource
{
    /// <summary>The underlying GPU handle (engine-internal — read by render systems).</summary>
    internal MaterialHandle Handle { get; }

    internal Material(IResourceCacheBackend cache, MaterialHandle handle) : base(cache, handle.Value)
    {
        Handle = handle;
    }
}
