using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_pass_io
{
    [NativeTypeName("const char *const *")]
    public sbyte** reads;

    [NativeTypeName("uint32_t")]
    public uint reads_count;

    [NativeTypeName("const char *const *")]
    public sbyte** writes;

    [NativeTypeName("uint32_t")]
    public uint writes_count;

    [NativeTypeName("uint32_t")]
    public uint cmd_slot;

    [NativeTypeName("uint32_t")]
    public uint load;
}
