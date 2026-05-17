using System.Runtime.CompilerServices;

namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_texture_data
{
    [NativeTypeName("uint8_t *")]
    public byte* pixels;

    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;

    [NativeTypeName("char[256]")]
    public _path_e__FixedBuffer path;

    [InlineArray(256)]
    public partial struct _path_e__FixedBuffer
    {
        public sbyte e0;
    }
}
