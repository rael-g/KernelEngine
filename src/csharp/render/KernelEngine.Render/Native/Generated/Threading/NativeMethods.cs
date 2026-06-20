using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_sync_std_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_frame_sync_handle")]
    public static extern KernelEngine.Render.Native.ke_frame_sync_handle frame_sync_std_create([NativeTypeName("uint32_t")] uint buffer_count, [NativeTypeName("uint32_t")] uint draw_capacity, [NativeTypeName("uint32_t")] uint point_capacity, [NativeTypeName("uint32_t")] uint spot_capacity, ke_error** out_error);
}
