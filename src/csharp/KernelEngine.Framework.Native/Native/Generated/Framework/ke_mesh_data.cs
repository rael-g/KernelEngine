using System.Runtime.CompilerServices;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_mesh_data
{
    public ke_vertex* vertices;

    [NativeTypeName("uint32_t")]
    public uint vertex_count;

    [NativeTypeName("uint16_t *")]
    public ushort* indices;

    [NativeTypeName("uint32_t")]
    public uint index_count;

    [NativeTypeName("int32_t")]
    public int material_index;

    [NativeTypeName("char[64]")]
    public _name_e__FixedBuffer name;

    [InlineArray(64)]
    public partial struct _name_e__FixedBuffer
    {
        public sbyte e0;
    }
}
