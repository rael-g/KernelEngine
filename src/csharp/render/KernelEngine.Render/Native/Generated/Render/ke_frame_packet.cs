using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_frame_packet
{
    [NativeTypeName("uint64_t")]
    public ulong frame_number;

    public ke_draw_command* draw_commands;

    [NativeTypeName("uint32_t")]
    public uint draw_count;

    [NativeTypeName("uint32_t")]
    public uint draw_capacity;

    [NativeTypeName("float[4]")]
    public _clear_color_e__FixedBuffer clear_color;

    [NativeTypeName("float[3]")]
    public _ambient_light_e__FixedBuffer ambient_light;

    public ke_shadow_map_handle active_shadow_map;

    public ke_frame_shadow shadow;

    public ke_draw_command* shadow_draw_commands;

    [NativeTypeName("uint32_t")]
    public uint shadow_draw_count;

    [NativeTypeName("uint32_t")]
    public uint shadow_draw_capacity;

    public ke_directional_light dir_light;

    [NativeTypeName("ke_bool")]
    public byte has_dir_light;

    public ke_point_light* point_lights;

    [NativeTypeName("uint32_t")]
    public uint point_light_count;

    [NativeTypeName("uint32_t")]
    public uint point_light_capacity;

    public ke_spot_light* spot_lights;

    [NativeTypeName("uint32_t")]
    public uint spot_light_count;

    [NativeTypeName("uint32_t")]
    public uint spot_light_capacity;

    public ke_frame_camera camera;

    public ke_texture_handle skybox_handle;

    [NativeTypeName("ke_bool")]
    public byte has_skybox;

    [NativeTypeName("ke_bool")]
    public byte ssao_enabled;

    public float ssao_radius;

    public float ssao_bias;

    public float ssao_strength;

    [NativeTypeName("ke_bool")]
    public byte tonemapping_enabled;

    public float exposure;

    public float gamma;

    [NativeTypeName("ke_bool")]
    public byte bloom_enabled;

    public float bloom_threshold;

    public float bloom_intensity;

    public ke_ui_draw_command* ui_draw_commands;

    [NativeTypeName("uint32_t")]
    public uint ui_draw_count;

    [NativeTypeName("uint32_t")]
    public uint ui_draw_capacity;

    [InlineArray(4)]
    public partial struct _clear_color_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(3)]
    public partial struct _ambient_light_e__FixedBuffer
    {
        public float e0;
    }
}

public partial struct ke_frame_packet
{
}

public partial struct ke_frame_packet
{
}
