namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_create_cubemap_cmd
{
    [NativeTypeName("uint32_t")]
    public uint face_size;

    [NativeTypeName("const uint8_t *")]
    public byte* pixels;
}
