using KernelEngine.Asset.Native;

namespace KernelEngine.Asset;

/// <summary>
/// Marker interface implemented by <see cref="IImageLoader"/> plugins that wrap a native
/// <c>ke_image_loader</c>. Lets downstream C-side consumers (e.g. <c>ke_asset_resolver</c>)
/// receive the raw vtable pointer without the Framework taking a hard reference on a
/// specific loader plugin.
/// </summary>
public unsafe interface INativeImageLoader
{
    /// <summary>Raw vtable pointer; lifetime tied to the wrapping <see cref="IImageLoader"/>.</summary>
    ke_image_loader* Native { get; }
}
