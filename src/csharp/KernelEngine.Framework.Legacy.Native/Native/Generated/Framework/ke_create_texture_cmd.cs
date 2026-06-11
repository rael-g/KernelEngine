namespace KernelEngine.Framework.Legacy.Native;

public unsafe partial struct ke_create_texture_cmd
{
    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;

    [NativeTypeName("const uint8_t *")]
    public byte* pixels;
}
