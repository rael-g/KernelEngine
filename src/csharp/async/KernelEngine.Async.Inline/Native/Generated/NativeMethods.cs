using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Async.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Async.Inline.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_async_inline", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_async_inline_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result async_inline_create([NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, [NativeTypeName("ke_async_handle *")] KernelEngine.Async.Native.ke_async_handle* out_async);

    [DllImport("ke_async_inline", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_async_inline_set_log_callback", ExactSpelling = true)]
    public static extern void async_inline_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
