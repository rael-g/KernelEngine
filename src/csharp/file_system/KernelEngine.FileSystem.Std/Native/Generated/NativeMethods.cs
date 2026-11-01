using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.FileSystem.Std.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_file_system_std", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_file_system_std_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result file_system_std_create([NativeTypeName("const ke_file_system_std_params *")] ke_file_system_std_params* @params, [NativeTypeName("ke_file_system_handle *")] KernelEngine.FileSystem.Native.ke_file_system_handle* out_file_system);

    [DllImport("ke_file_system_std", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_file_system_std_set_log_callback", ExactSpelling = true)]
    public static extern void file_system_std_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
