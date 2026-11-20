using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Assembly.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Assembly.Default.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_assembly_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_assembly_default_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result assembly_default_create([NativeTypeName("ke_configuration *")] KernelEngine.Configuration.Native.ke_configuration* configuration, [NativeTypeName("ke_assembly_handle *")] KernelEngine.Assembly.Native.ke_assembly_handle* out_assembly);

    [DllImport("ke_assembly_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_assembly_default_set_log_callback", ExactSpelling = true)]
    public static extern void assembly_default_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
