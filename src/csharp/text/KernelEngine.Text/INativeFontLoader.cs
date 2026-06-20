using KernelEngine.Text.Native;

namespace KernelEngine.Text;

/// <summary>
/// Marker interface implemented by <see cref="IFontLoader"/> plugins that wrap a native
/// <c>ke_font_loader</c>. Lets downstream C-side consumers (e.g. <c>ke_asset_resolver</c>)
/// receive the raw vtable pointer without the Framework taking a hard reference on a
/// specific loader plugin.
/// </summary>
public unsafe interface INativeFontLoader
{
    /// <summary>Raw vtable pointer; lifetime tied to the wrapping <see cref="IFontLoader"/>.</summary>
    ke_font_loader* Native { get; }
}
