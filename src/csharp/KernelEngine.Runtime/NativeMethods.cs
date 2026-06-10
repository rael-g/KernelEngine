using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Runtime;

/// <summary>
/// Hand-rolled P/Invoke for ke_runtime_create. Minimal until R2.5c brings the
/// real scheduler core surface (ke_system_ctx, wave dispatch, defer queue).
/// </summary>
internal static unsafe partial class NativeMethods
{
    [DllImport("ke_runtime", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_runtime_create", ExactSpelling = true)]
    internal static extern ke_result runtime_create(
        ke_allocator*       alloc,
        ke_ecs*             ecs,
        ke_runtime_params*  @params,
        ke_runtime**        out_runtime);
}

/// <summary>
/// Layout-compatible mirror of the C <c>ke_runtime_params</c> struct.
/// One <c>int</c> reserved field; expanded with phase config + logger in R2.5c.
/// </summary>
internal struct ke_runtime_params
{
    public int reserved;
}
