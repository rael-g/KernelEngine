namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_mesh_shape_data
{
    public ke_vertex* vertices;

    [NativeTypeName("uint32_t")]
    public uint vertex_count;

    [NativeTypeName("uint16_t *")]
    public ushort* indices;

    [NativeTypeName("uint32_t")]
    public uint index_count;
}
