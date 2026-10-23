using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Input.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result input_create(ke_input_handle* out_input);

    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_default_set_log_callback", ExactSpelling = true)]
    public static extern void input_default_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
