using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_threading_std", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_sync_std_create", ExactSpelling = true)]
    public static extern ke_result frame_sync_std_create([NativeTypeName("uint32_t")] uint buffer_count, [NativeTypeName("uint32_t")] uint draw_capacity, [NativeTypeName("uint32_t")] uint point_capacity, [NativeTypeName("uint32_t")] uint spot_capacity, [NativeTypeName("ke_frame_sync_handle *")] KernelEngine.Render.Native.ke_frame_sync_handle* @out, ke_error** out_error);
}
