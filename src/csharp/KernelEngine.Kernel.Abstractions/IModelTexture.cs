namespace KernelEngine.Kernel;

/// <summary>
/// Read-only view of a decoded RGBA8 texture loaded as part of an <see cref="IModel"/>.
/// Backing memory is owned by the parent <see cref="IModel"/> and freed on dispose.
/// </summary>
public interface IModelTexture
{
    /// <summary>Source file path, or empty for embedded textures.</summary>
    string Path { get; }

    /// <summary>Texture width in pixels.</summary>
    uint Width { get; }

    /// <summary>Texture height in pixels.</summary>
    uint Height { get; }

    /// <summary>RGBA8 pixel data, <c>Width × Height × 4</c> bytes.</summary>
    ReadOnlySpan<byte> Pixels { get; }
}
