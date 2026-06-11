using System.Runtime.CompilerServices;

namespace KernelEngine.Framework.Legacy.Native;

public partial struct ke_material_data
{
    public float base_color_r;

    public float base_color_g;

    public float base_color_b;

    public float base_color_a;

    public float metallic;

    public float roughness;

    [NativeTypeName("int32_t")]
    public int albedo_texture_index;

    [NativeTypeName("int32_t")]
    public int normal_map_texture_index;

    [NativeTypeName("char[64]")]
    public _name_e__FixedBuffer name;

    [InlineArray(64)]
    public partial struct _name_e__FixedBuffer
    {
        public sbyte e0;
    }
}
