namespace KernelEngine.Common.Native;

public unsafe partial struct ke_arena
{
    [NativeTypeName("uint8_t *")]
    public byte* buffer;

    [NativeTypeName("size_t")]
    public nuint capacity;

    [NativeTypeName("size_t")]
    public nuint offset;
}
