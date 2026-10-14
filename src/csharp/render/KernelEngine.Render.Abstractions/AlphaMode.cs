namespace KernelEngine.Render;

/// <summary>
/// How a material's alpha is used. Mirrors the native <c>ke_alpha_mode</c>.
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
