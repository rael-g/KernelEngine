using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Configuration.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_configuration_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_toml_create", ExactSpelling = true)]
    public static extern ke_configuration_source_handle configuration_toml_create([NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_configuration_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_toml_set_log_callback", ExactSpelling = true)]
    public static extern void configuration_toml_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
