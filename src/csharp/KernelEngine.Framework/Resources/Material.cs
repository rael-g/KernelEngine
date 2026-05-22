using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A ref-counted GPU material. Create via <see cref="ResourceManager"/>; assign to a mesh node
/// instead of juggling a raw <see cref="MaterialHandle"/>.
/// </summary>
public sealed class Material : Resource
{
    private readonly IResourceFactory _factory;

    /// <summary>The underlying GPU handle (engine-internal — read by render systems).</summary>
    internal MaterialHandle Handle { get; }

    internal Material(IResourceFactory factory, MaterialHandle handle)
    {
        _factory = factory;
        Handle = handle;
    }

    protected override void DestroyNative() => _factory.DestroyMaterial(Handle);
}
