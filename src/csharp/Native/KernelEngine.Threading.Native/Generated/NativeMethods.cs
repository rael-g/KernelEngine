using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Threading.Native;

public static unsafe partial class NativeMethods
{
    // ── ke_thread ─────────────────────────────────────────────────────────────

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_thread_create", ExactSpelling = true)]
    public static extern ke_result thread_create(
        ke_allocator*        alloc,
        ke_thread_desc*      desc,
        ke_thread**          @out);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_thread_join", ExactSpelling = true)]
    public static extern void thread_join(ke_thread* t);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_thread_destroy", ExactSpelling = true)]
    public static extern void thread_destroy(ke_thread* t, ke_allocator* alloc);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_thread_set_current_name", ExactSpelling = true)]
    public static extern void thread_set_current_name(
        [NativeTypeName("const char *")] sbyte* name);

    // ── ke_semaphore ──────────────────────────────────────────────────────────

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_semaphore_create", ExactSpelling = true)]
    public static extern ke_result semaphore_create(
        ke_allocator*  alloc,
        uint           initial,
        ke_semaphore** @out);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_semaphore_signal", ExactSpelling = true)]
    public static extern void semaphore_signal(ke_semaphore* s);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_semaphore_wait", ExactSpelling = true)]
    public static extern void semaphore_wait(ke_semaphore* s);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_semaphore_destroy", ExactSpelling = true)]
    public static extern void semaphore_destroy(ke_semaphore* s, ke_allocator* alloc);
}
