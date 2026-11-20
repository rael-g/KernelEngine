using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Async.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Async.Enki.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_async_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_async_enki_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result async_enki_create([NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, [NativeTypeName("ke_async_handle *")] KernelEngine.Async.Native.ke_async_handle* out_async);

    [DllImport("ke_async_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_async_enki_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* async_enki_parts([NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_async_enki", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_async_enki_set_log_callback", ExactSpelling = true)]
    public static extern void async_enki_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
