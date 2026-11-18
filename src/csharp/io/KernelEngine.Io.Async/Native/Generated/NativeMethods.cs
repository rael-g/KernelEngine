using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Async.Native;
using KernelEngine.FileSystem.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Io.Async.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_io_async", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_io_async_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result io_async_create([NativeTypeName("ke_async *")] KernelEngine.Async.Native.ke_async* async, [NativeTypeName("ke_file_system *")] KernelEngine.FileSystem.Native.ke_file_system* file_system, [NativeTypeName("ke_io_handle *")] KernelEngine.Io.Native.ke_io_handle* out_io);

    [DllImport("ke_io_async", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_io_async_set_log_callback", ExactSpelling = true)]
    public static extern void io_async_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
