namespace KernelEngine.Render.Bgfx;

/// <summary>
/// Bound to the Project file's <c>[render]</c> section. Holds scene-wide
/// render defaults that aren't bgfx-init-time (which go in
/// <c>[runtime.renderer]</c>) but per-frame state owned by the framework's
/// render pipeline.
/// </summary>
public sealed class RenderOptions
{
    /// <summary>
    /// Default background color, written into the packet every frame unless a
    /// scene's contributor overrides it. TOML format is a 4-element array of
    /// floats in [0..1]: <c>clear_color = [r, g, b, a]</c>. Absent = framework
    /// default (renderer's clear color stays whatever bgfx ships with).
    /// </summary>
    public float[]? ClearColor { get; set; }
}
