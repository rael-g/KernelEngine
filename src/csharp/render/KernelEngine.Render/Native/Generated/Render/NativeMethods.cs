using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_packet_create", ExactSpelling = true)]
    public static extern bool frame_packet_create([NativeTypeName("const ke_frame_packet_params *")] ke_frame_packet_params* @params, ke_frame_packet** out_packet, ke_error** out_error);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_packet_destroy", ExactSpelling = true)]
    public static extern void frame_packet_destroy(ke_frame_packet* packet);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_packet_reset", ExactSpelling = true)]
    public static extern void frame_packet_reset(ke_frame_packet* packet);
}
