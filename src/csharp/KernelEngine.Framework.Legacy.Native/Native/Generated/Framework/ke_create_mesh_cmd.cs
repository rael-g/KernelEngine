namespace KernelEngine.Framework.Legacy.Native;

public unsafe partial struct ke_create_mesh_cmd
{
    [NativeTypeName("const ke_vertex *")]
    public ke_vertex* vertices;

    [NativeTypeName("uint32_t")]
    public uint vertex_count;

    [NativeTypeName("const uint16_t *")]
    public ushort* indices;

    [NativeTypeName("uint32_t")]
    public uint index_count;
}
