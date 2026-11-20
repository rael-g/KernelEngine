using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.FileSystem.Native;
using KernelEngine.Io.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Io.Std.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_io_std", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_io_std_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result io_std_create([NativeTypeName("ke_file_system *")] KernelEngine.FileSystem.Native.ke_file_system* file_system, [NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, [NativeTypeName("ke_io_handle *")] KernelEngine.Io.Native.ke_io_handle* out_io);

    [DllImport("ke_io_std", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_io_std_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* io_std_parts([NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_io_std", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_io_std_set_log_callback", ExactSpelling = true)]
    public static extern void io_std_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
