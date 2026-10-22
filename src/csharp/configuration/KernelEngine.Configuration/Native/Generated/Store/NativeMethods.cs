using System.Runtime.InteropServices;

using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;

namespace KernelEngine.Configuration.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_configuration", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_create", ExactSpelling = true)]
    public static extern ke_configuration_handle configuration_create([NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_configuration", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_set_log_callback", ExactSpelling = true)]
    public static extern void configuration_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
