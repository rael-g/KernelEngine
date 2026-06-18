using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_sync_std_create", ExactSpelling = true)]
    public static extern ke_result frame_sync_std_create(ke_allocator* alloc, [NativeTypeName("uint32_t")] uint buffer_count, [NativeTypeName("uint32_t")] uint draw_capacity, [NativeTypeName("uint32_t")] uint point_capacity, [NativeTypeName("uint32_t")] uint spot_capacity, ke_frame_sync_handle* @out, ke_error** out_error);
}
