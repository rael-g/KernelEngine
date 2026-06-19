using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_mesh_component
{
    public ke_mesh_handle mesh;

    public ke_material_handle material;

    [NativeTypeName("char[32]")]
    public _primitive_e__FixedBuffer primitive;

    [NativeTypeName("float[4]")]
    public _color_e__FixedBuffer color;

    [InlineArray(32)]
    public partial struct _primitive_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(4)]
    public partial struct _color_e__FixedBuffer
    {
        public float e0;
    }
}
