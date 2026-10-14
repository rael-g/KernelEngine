namespace KernelEngine.Render;

/// <summary>Refers to a mesh held by the render backend; zero is the invalid handle.</summary>
public readonly record struct MeshHandle(uint Value)
{
    public static readonly MeshHandle None = new(0u);
    public bool IsValid => Value != 0u;
}

/// <summary>Refers to a texture or cubemap held by the render backend; zero is the invalid handle.</summary>
public readonly record struct TextureHandle(uint Value)
{
    public static readonly TextureHandle None = new(0u);
    public bool IsValid => Value != 0u;
}

/// <summary>Refers to a material held by the render backend; zero is the invalid handle.</summary>
public readonly record struct MaterialHandle(uint Value)
{
    public static readonly MaterialHandle None = new(0u);
    public bool IsValid => Value != 0u;
}

/// <summary>Refers to a shadow map; zero is the invalid handle.</summary>
public readonly record struct ShadowMapHandle(uint Value)
{
    public static readonly ShadowMapHandle None = new(0u);
    public bool IsValid => Value != 0u;
}

/// <summary>Refers to a glyph table registered through <see cref="IRenderResources.LoadFont"/>; zero is the invalid handle.</summary>
public readonly record struct FontHandle(uint Value)
{
    public static readonly FontHandle None = new(0u);
    public bool IsValid => Value != 0u;
}

/// <summary>
/// One baked glyph's layout and atlas coordinates, in pixels, as
/// <see cref="IRenderResources.LoadFont"/> takes them.
/// </summary>
public readonly record struct FontGlyph(
    uint  Codepoint,
    float U0, float V0, float U1, float V1,
    float BearingX, float BearingY,
    float Width, float Height,
    float AdvanceX);
