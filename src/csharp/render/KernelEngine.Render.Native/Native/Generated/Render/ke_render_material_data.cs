using System.Runtime.CompilerServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_render_material_data
{
    [NativeTypeName("float[4]")]
    public _base_color_e__FixedBuffer base_color;

    public float metallic;

    public float roughness;

    public float alpha_cutoff;

    public float ior;

    public float distortion_strength;

    [NativeTypeName("ke_gpu_texture_view")]
    public ulong albedo;

    [NativeTypeName("ke_gpu_texture_view")]
    public ulong normal_map;

    [InlineArray(4)]
    public partial struct _base_color_e__FixedBuffer
    {
        public float e0;
    }
}
