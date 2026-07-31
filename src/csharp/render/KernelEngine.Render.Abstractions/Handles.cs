namespace KernelEngine.Render;

public readonly record struct MeshHandle(uint Value)
{
    public static readonly MeshHandle None = new(uint.MaxValue);
    public bool IsValid => Value != uint.MaxValue;
}

public readonly record struct TextureHandle(uint Value)
{
    public static readonly TextureHandle None = new(uint.MaxValue);
    public bool IsValid => Value != uint.MaxValue;
}

public readonly record struct MaterialHandle(uint Value)
{
    public static readonly MaterialHandle None = new(uint.MaxValue);
    public bool IsValid => Value != uint.MaxValue;
}

public readonly record struct ShadowMapHandle(uint Value)
{
    public static readonly ShadowMapHandle None = new(uint.MaxValue);
    public bool IsValid => Value != uint.MaxValue;
}

/// <summary>A font's glyph table registered with the UI overlay pass via <see cref="IRenderResources.LoadFont"/>.</summary>
public readonly record struct FontHandle(uint Value)
{
    public static readonly FontHandle None = new(uint.MaxValue);
    public bool IsValid => Value != uint.MaxValue;
}

/// <summary>
/// One baked glyph's layout + atlas-sampling info, in pixels — the shape
/// <see cref="IRenderResources.LoadFont"/> needs, independent of any particular
/// font-loader plugin's own glyph type (this project doesn't depend on Text).
/// </summary>
public readonly record struct FontGlyph(
    uint  Codepoint,
    float U0, float V0, float U1, float V1,
    float BearingX, float BearingY,
    float Width, float Height,
    float AdvanceX);
