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
