using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_configuration", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result configuration_create(ke_configuration_handle* out_store);

    [DllImport("ke_configuration", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_set_log_callback", ExactSpelling = true)]
    public static extern void configuration_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
