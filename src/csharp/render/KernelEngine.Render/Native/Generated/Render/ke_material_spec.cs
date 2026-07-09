using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_material_spec
{
    [NativeTypeName("float[4]")]
    public _base_color_e__FixedBuffer base_color;

    public float metallic;

    public float roughness;

    [NativeTypeName("char[256]")]
    public _albedo_path_e__FixedBuffer albedo_path;

    [NativeTypeName("char[256]")]
    public _normal_path_e__FixedBuffer normal_path;

    public ke_alpha_mode alpha_mode;

    public float alpha_cutoff;

    [InlineArray(4)]
    public partial struct _base_color_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(256)]
    public partial struct _albedo_path_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(256)]
    public partial struct _normal_path_e__FixedBuffer
    {
        public sbyte e0;
    }
}
