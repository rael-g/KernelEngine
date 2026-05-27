namespace KernelEngine.Render.Bgfx;

/// <summary>
/// Project-level settings for the bgfx render plugin. Hydrated from the
/// <c>[runtime.renderer]</c> section of <c>Project.toml</c> when configured,
/// otherwise these compile-time defaults apply (chapter 16 §2.4).
/// </summary>
public sealed class BgfxRendererOptions
{
    /// <summary>
    /// Directory holding compiled SPIR-V shaders. Relative paths are resolved against
    /// <see cref="AppContext.BaseDirectory"/> at plugin construction time, so the same
    /// value works whether the project ships shaders next to the executable or in a
    /// shared location.
    /// </summary>
    public string ShaderPath { get; set; } = "shaders";

    /// <summary>When true, the backend caps frame submission to the display refresh rate.</summary>
    public bool Vsync { get; set; } = true;
}
