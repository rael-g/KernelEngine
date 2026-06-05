using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A ref-counted GPU texture (2D or cubemap). Create via <see cref="ResourceManager"/>; assign to a
/// material instead of juggling a raw <see cref="TextureHandle"/>.
/// </summary>
public sealed class Texture : Resource
{
    /// <summary>The underlying GPU handle (engine-internal — read by materials/render systems).</summary>
    internal TextureHandle Handle { get; }

    internal Texture(IResourceCacheBackend cache, TextureHandle handle) : base(cache, handle.Value)
    {
        Handle = handle;
    }
}
