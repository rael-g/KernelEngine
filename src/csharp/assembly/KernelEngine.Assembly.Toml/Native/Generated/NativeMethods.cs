using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Assembly.Native;
using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Assembly.Toml.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_assembly_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_assembly_toml_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result assembly_toml_create([NativeTypeName("ke_file_system *")] KernelEngine.FileSystem.Native.ke_file_system* file_system, [NativeTypeName("ke_composition_source_handle *")] KernelEngine.Assembly.Native.ke_composition_source_handle* out_source);

    [DllImport("ke_assembly_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_assembly_toml_set_log_callback", ExactSpelling = true)]
    public static extern void assembly_toml_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
