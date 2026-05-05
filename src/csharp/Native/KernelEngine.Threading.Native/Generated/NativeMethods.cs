using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Threading.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_std_create", ExactSpelling = true)]
    public static extern ke_result thread_std_create(ke_allocator* alloc, [NativeTypeName("const ke_thread_desc *")] ke_thread_desc* desc, ke_thread** @out);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_set_current_name", ExactSpelling = true)]
    public static extern void thread_set_current_name([NativeTypeName("const char *")] sbyte* name);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_get_current_name", ExactSpelling = true)]
    [return: NativeTypeName("const char *")]
    public static extern sbyte* thread_get_current_name();

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_assert_current", ExactSpelling = true)]
    public static extern void thread_assert_current([NativeTypeName("const char *")] sbyte* expected_name);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_semaphore_std_create", ExactSpelling = true)]
    public static extern ke_result semaphore_std_create(ke_allocator* alloc, [NativeTypeName("uint32_t")] uint initial, ke_semaphore** @out);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_sync_std_create", ExactSpelling = true)]
    public static extern ke_result frame_sync_std_create(ke_allocator* alloc, [NativeTypeName("uint32_t")] uint buffer_count, [NativeTypeName("uint32_t")] uint draw_capacity, [NativeTypeName("uint32_t")] uint point_capacity, [NativeTypeName("uint32_t")] uint spot_capacity, ke_frame_sync** @out);
}
