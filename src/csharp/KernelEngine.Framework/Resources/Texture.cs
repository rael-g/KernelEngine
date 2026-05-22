using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A ref-counted GPU texture (2D or cubemap). Create via <see cref="ResourceManager"/>; assign to a
/// material instead of juggling a raw <see cref="TextureHandle"/>.
/// </summary>
public sealed class Texture : Resource
{
    private readonly IResourceFactory _factory;

    /// <summary>The underlying GPU handle (engine-internal — read by materials/render systems).</summary>
    internal TextureHandle Handle { get; }

    internal Texture(IResourceFactory factory, TextureHandle handle)
    {
        _factory = factory;
        Handle = handle;
    }

    protected override void DestroyNative() => _factory.DestroyTexture(Handle);
}
