using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_configuration_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_toml_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result configuration_toml_create(ke_configuration_source_handle* out_source);

    [DllImport("ke_configuration_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_toml_set_log_callback", ExactSpelling = true)]
    public static extern void configuration_toml_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
