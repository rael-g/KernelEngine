namespace KernelEngine.Render;

/// <summary>
/// glTF 2.0-aligned material alpha mode. Mirrors the native <c>ke_alpha_mode</c>.
/// <see cref="Opaque"/> and <see cref="Mask"/> both shade through the G-buffer;
/// <see cref="Blend"/> is the only mode the transparent forward pass shades.
/// </summary>
public enum AlphaMode
{
    /// <summary>Alpha channel ignored. The default.</summary>
    Opaque = 0,

    /// <summary>Opaque with a hard discard below the material's alpha cutoff — not blending.</summary>
    Mask = 1,

    /// <summary>Shaded by the transparent forward pass, blended into the frame.</summary>
    Blend = 2,
}
