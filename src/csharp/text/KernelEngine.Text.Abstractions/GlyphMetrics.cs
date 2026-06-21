namespace KernelEngine.Text;

/// <summary>
/// Per-glyph layout + atlas-sampling info, in pixels at the font's baked size. Mirrors
/// the C kernel's <c>ke_glyph_metrics</c>.
/// </summary>
/// <param name="Codepoint">The Unicode codepoint this glyph represents.</param>
/// <param name="U0">Source-rect top-left U in the atlas (normalized).</param>
/// <param name="V0">Source-rect top-left V in the atlas (normalized).</param>
/// <param name="U1">Source-rect bottom-right U.</param>
/// <param name="V1">Source-rect bottom-right V.</param>
/// <param name="BearingX">Pen-relative X shift to the glyph's left edge (pixels).</param>
/// <param name="BearingY">Baseline-relative Y shift to the glyph's top edge (pixels, +up).</param>
/// <param name="Width">Glyph width in pixels (matches the destination quad size).</param>
/// <param name="Height">Glyph height in pixels.</param>
/// <param name="AdvanceX">Horizontal pen advance after this glyph (pixels).</param>
public readonly record struct GlyphMetrics(
    uint  Codepoint,
    float U0, float V0, float U1, float V1,
    float BearingX, float BearingY,
    float Width, float Height,
    float AdvanceX);
