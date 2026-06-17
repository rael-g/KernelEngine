namespace KernelEngine.Kernel;

/// <summary>
/// Read-only view of a decoded RGBA8 image. Backing memory is owned by the loader and freed on
/// <see cref="IDisposable.Dispose"/>.
/// </summary>
public interface IImageData : IDisposable
{
    /// <summary>Source file path.</summary>
    string Path { get; }

    /// <summary>Image width in pixels.</summary>
    uint Width { get; }

    /// <summary>Image height in pixels.</summary>
    uint Height { get; }

    /// <summary>RGBA8 pixel data, <c>Width × Height × 4</c> bytes.</summary>
    ReadOnlySpan<byte> Pixels { get; }
}
