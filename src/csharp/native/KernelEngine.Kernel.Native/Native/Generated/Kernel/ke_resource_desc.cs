namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_resource_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public ke_resource_type type;

    public ke_resource_format format;

    public ke_resource_size_mode size_mode;

    [NativeTypeName("uint32_t")]
    public uint width;

    [NativeTypeName("uint32_t")]
    public uint height;

    public float scale_x;

    public float scale_y;

    [NativeTypeName("uint32_t")]
    public uint element_count;

    [NativeTypeName("uint32_t")]
    public uint element_stride;
}
