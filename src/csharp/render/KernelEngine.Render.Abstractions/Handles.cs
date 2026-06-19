namespace KernelEngine.Kernel;

public readonly record struct MeshHandle(uint Value)
{
    public static readonly MeshHandle None = new(uint.MaxValue);
    public bool IsValid => Value != uint.MaxValue;
}

public readonly record struct TextureHandle(uint Value)
{
    public static readonly TextureHandle None = new(uint.MaxValue);
    public bool IsValid => Value != uint.MaxValue;

    /// <summary>Handle 0 is always the built-in 1×1 white texture created at renderer init.</summary>
    public static readonly TextureHandle White = new(0);
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
