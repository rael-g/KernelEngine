using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Io.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_configuration_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_toml_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result configuration_toml_create([NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, ke_configuration_source_handle* out_source);

    [DllImport("ke_configuration_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_toml_set_log_callback", ExactSpelling = true)]
    public static extern void configuration_toml_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
