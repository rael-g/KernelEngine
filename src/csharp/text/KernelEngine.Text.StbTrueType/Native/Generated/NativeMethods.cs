using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Text.StbTrueType.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_text_stb_truetype", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_font_loader_stb_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result font_loader_stb_create([NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, [NativeTypeName("ke_font_loader_handle *")] KernelEngine.Text.Native.ke_font_loader_handle* out_loader);

    [DllImport("ke_text_stb_truetype", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_text_stb_truetype_set_log_callback", ExactSpelling = true)]
    public static extern void text_stb_truetype_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
