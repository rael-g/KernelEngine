using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public partial struct ke_frame_packet_params
{
    [NativeTypeName("uint32_t")]
    public uint draw_capacity;

    [NativeTypeName("uint32_t")]
    public uint shadow_draw_capacity;

    [NativeTypeName("uint32_t")]
    public uint point_light_capacity;

    [NativeTypeName("uint32_t")]
    public uint spot_light_capacity;

    [NativeTypeName("uint32_t")]
    public uint ui_draw_capacity;
}
