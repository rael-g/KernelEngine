using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Text.StbTrueType.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_text_stb_truetype", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_font_loader_stb_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result font_loader_stb_create([NativeTypeName("ke_font_loader_handle *")] KernelEngine.Text.Native.ke_font_loader_handle* out_loader);

    [DllImport("ke_text_stb_truetype", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_text_stb_truetype_set_log_callback", ExactSpelling = true)]
    public static extern void text_stb_truetype_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
