namespace KernelEngine.Asset.StbImage;

/// <summary>
/// The parts of <see cref="ImageLoader"/> that express the native surface in C# terms
/// rather than mirroring it: the <see cref="IImageData"/> view (deferred-copy, reading
/// straight through the native <c>ke_texture_data*</c> until disposed) and the
/// worker-thread wrapping <see cref="Task.Run(Func{IImageData})"/> gives a synchronous
/// native decode. Everything that is a direct image of the C ABI is generated in
/// <c>Generated/ImageLoader.g.cs</c>.
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
