using System.Runtime.InteropServices;

using KernelEngine.FileSystem.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Io.Pool.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_io_pool", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_io_pool_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result io_pool_create([NativeTypeName("const ke_io_pool_params *")] ke_io_pool_params* @params, [NativeTypeName("ke_io_handle *")] KernelEngine.Io.Native.ke_io_handle* out_io);

    [DllImport("ke_io_pool", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_io_pool_set_log_callback", ExactSpelling = true)]
    public static extern void io_pool_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
