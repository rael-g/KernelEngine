using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Async;
using global::KernelEngine.Logger;

using KernelEngine.Async.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Async.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_async_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_async_enki_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result async_enki_create([NativeTypeName("const ke_async_config *")] global::KernelEngine.Async.AsyncConfig* config, [NativeTypeName("ke_async_handle *")] KernelEngine.Async.Native.ke_async_handle* out_async);

    [DllImport("ke_async_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_async_enki_set_log_callback", ExactSpelling = true)]
    public static extern void async_enki_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
