namespace KernelEngine.Render.Bgfx;

/// <summary>
/// Project-level settings for the bgfx render plugin. Hydrated from the
/// <c>[runtime.renderer]</c> section of <c>Project.toml</c> when configured,
/// otherwise these compile-time defaults apply (chapter 16 §2.4).
/// </summary>
public sealed class BgfxRendererOptions
{
    /// <summary>
    /// Root directory holding compiled shaders. The renderer appends a per-backend
    /// subdirectory (e.g. <c>spirv/</c>, <c>dx11/</c>) automatically. Relative paths
    /// are resolved against <see cref="AppContext.BaseDirectory"/> at plugin construction
    /// time, so the same value works whether shaders are next to the executable or in a
    /// shared location. Configure via <c>[runtime.renderer] shader_path = "…"</c> in
    /// <c>Project.toml</c>.
    /// </summary>
    public string ShaderPath { get; set; } = "shaders";

    /// <summary>When true, the backend caps frame submission to the display refresh rate.</summary>
    public bool Vsync { get; set; } = true;

    /// <summary>
    /// Graphics backend to initialise. Defaults to <see cref="BgfxBackend.Auto"/>, which lets
    /// the bgfx factory choose the best backend for the current platform. Override via
    /// <c>[runtime.renderer] backend = "direct3d11"</c> in <c>Project.toml</c> or via
    /// <c>services.Configure&lt;BgfxRendererOptions&gt;(o =&gt; o.Backend = BgfxBackend.Vulkan)</c>.
    /// </summary>
    public BgfxBackend Backend { get; set; } = BgfxBackend.Auto;
}
