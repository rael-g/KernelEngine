using System.Runtime.InteropServices;
using KernelEngine.Asset;
using KernelEngine.Common.Native;

namespace KernelEngine.Asset.StbImage;

/// <summary>stb_image-backed <see cref="IImageLoader"/>.</summary>
public sealed unsafe class ImageLoader : IImageLoader, INativeImageLoader
{
    private ke_image_loader* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_image_loader*, void> _destroy;

    internal ImageLoader(ke_image_loader_handle handle)
    {
        _native = handle.@ref;
        _destroy = handle.destroy;
    }

    ke_image_loader* INativeImageLoader.Native => _native;

    public IImageData LoadImage(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);

        var bytes = System.Text.Encoding.UTF8.GetByteCount(path) + 1;
        var pathPtr = Marshal.AllocHGlobal(bytes);
        try
        {
            var span = new Span<byte>((void*)pathPtr, bytes);
            var written = System.Text.Encoding.UTF8.GetBytes(path, span);
            span[written] = 0;

            ke_error* err = null;
            ke_texture_data* data = _native->load_image(_native, (sbyte*)pathPtr, &err);
            if (data == null) throw KernelError.FromNative(err, "load_image");
            return new ImageData(_native, data);
        }
        finally
        {
            Marshal.FreeHGlobal(pathPtr);
        }
    }

    public Task<IImageData> LoadImageAsync(string path)
        => Task.Run<IImageData>(() => LoadImage(path));

    public void Dispose()
    {
        if (_native == null) return;
        if (_destroy != null) _destroy(_native);
        _native = null;
    }
}

/// <summary>Owns a <see cref="ke_texture_data"/> returned by the loader; frees it on dispose.</summary>
internal sealed unsafe class ImageData : IImageData
{
    private readonly ke_image_loader* _owner;
    private ke_texture_data* _data;

    internal ImageData(ke_image_loader* owner, ke_texture_data* data)
    {
        _owner = owner;
        _data = data;
        Path = new string((sbyte*)&data->path);
    }

    public string Path { get; }
    public uint Width => _data != null ? _data->width : 0u;
    public uint Height => _data != null ? _data->height : 0u;

    public ReadOnlySpan<byte> Pixels
    {
        get
        {
            if (_data == null || _data->pixels == null) return ReadOnlySpan<byte>.Empty;
            var len = checked((int)(_data->width * _data->height * 4u));
            return new ReadOnlySpan<byte>(_data->pixels, len);
        }
    }

    public void Dispose()
    {
        if (_data == null) return;
        _owner->free_image(_owner, _data);
        _data = null;
    }
}
