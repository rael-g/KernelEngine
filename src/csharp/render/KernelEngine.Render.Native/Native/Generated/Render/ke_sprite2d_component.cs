using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_sprite2d_component
{
    [NativeTypeName("char[128]")]
    public _texture_e__FixedBuffer texture;

    [NativeTypeName("ke_vec4")]
    public KernelEngine.Common.Native.ke_vec4 region;

    [NativeTypeName("ke_vec2")]
    public KernelEngine.Common.Native.ke_vec2 size;

    [NativeTypeName("ke_vec2")]
    public KernelEngine.Common.Native.ke_vec2 pivot;

    [NativeTypeName("uint8_t")]
    public byte flip_h;

    [NativeTypeName("uint8_t")]
    public byte flip_v;

    [NativeTypeName("ke_vec4")]
    public KernelEngine.Common.Native.ke_vec4 color;

    [NativeTypeName("uint32_t")]
    public uint alpha_mode;

    public float alpha_cutoff;

    public ke_texture_handle texture_handle;

    [NativeTypeName("uint8_t")]
    public byte attached;

    [InlineArray(128)]
    public partial struct _texture_e__FixedBuffer
    {
        public sbyte e0;
    }
}
