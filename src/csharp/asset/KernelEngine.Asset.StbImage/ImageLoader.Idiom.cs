namespace KernelEngine.Asset.StbImage;

/// <summary>
/// The stb_image loader over <c>ke_image_loader</c>. The <see cref="IImageData"/> it returns reads
/// the native pixels in place until it is disposed.
/// </summary>
public unsafe partial class ImageLoader : IImageLoader
{
    /// <inheritdoc/>
    IImageData IImageLoader.LoadImage(string path)
    {
        var data = LoadImage(path);
        var native = ((INativeImageLoader)this).Native;
        return new ImageData(native, data);
    }

    /// <inheritdoc/>
    public Task<IImageData> LoadImageAsync(string path)
        => Task.Run<IImageData>(() => ((IImageLoader)this).LoadImage(path));
}
