namespace KernelEngine.Asset;

/// <summary>
/// Decodes a 2D image file (PNG/JPG/BMP/...) into <see cref="IImageData"/> (RGBA8). Concrete
/// implementations live in format plugins (e.g. <c>KernelEngine.Asset.StbImage</c>).
/// </summary>
public interface IImageLoader : IDisposable
{
    /// <summary>Decodes an image synchronously. Caller disposes the returned <see cref="IImageData"/>.</summary>
    IImageData LoadImage(string path);

    /// <summary>
    /// Decodes an image on a worker thread (so ke.sim doesn't block on disk I/O + decode).
    /// Caller disposes the returned <see cref="IImageData"/>.
    /// </summary>
    Task<IImageData> LoadImageAsync(string path);
}
