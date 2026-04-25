namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_frame_packet
{
    [NativeTypeName("uint64_t")]
    public ulong frame_number;

    public ke_draw_command* draw_commands;

    [NativeTypeName("uint32_t")]
    public uint draw_count;

    [NativeTypeName("uint32_t")]
    public uint draw_capacity;

    public ke_frame_shadow shadow;

    public ke_draw_command* shadow_draw_commands;

    [NativeTypeName("uint32_t")]
    public uint shadow_draw_count;

    [NativeTypeName("uint32_t")]
    public uint shadow_draw_capacity;

    public ke_directional_light dir_light;

    public bool has_dir_light;

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

    [NativeTypeName("uint32_t")]
    public uint skybox_handle;

    public bool has_skybox;
}
