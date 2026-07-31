using System.Runtime.InteropServices;

namespace KernelEngine.Asset.StbImage;

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
