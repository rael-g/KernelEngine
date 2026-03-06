using System.Runtime.InteropServices;

namespace KernelEngine.Asset.Assimp.Native;

/// <summary>Decoded RGBA8 texture data returned by <c>ke_asset_loader::load_model</c>.</summary>
[StructLayout(LayoutKind.Sequential)]
public unsafe partial struct ke_texture_data
{
    /// <summary>RGBA8 pixels, row-major, <c>width * height * 4</c> bytes.</summary>
    [NativeTypeName("uint8_t *")]
    public byte* pixels;

    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;

    /// <summary>Source path; empty for embedded textures.</summary>
    [NativeTypeName("char[256]")]
    public fixed sbyte path[256];
}
