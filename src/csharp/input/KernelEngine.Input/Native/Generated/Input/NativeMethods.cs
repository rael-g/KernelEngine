using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Input.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result input_create(ke_input_handle* out_input);

    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_default_set_log_callback", ExactSpelling = true)]
    public static extern void input_default_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
