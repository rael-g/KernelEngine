using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Text.StbTrueType.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_text_stb_truetype", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_font_loader_stb_create", ExactSpelling = true)]
    public static extern ke_result font_loader_stb_create([NativeTypeName("const ke_font_loader_stb_params *")] ke_font_loader_stb_params* @params, [NativeTypeName("ke_font_loader_handle *")] KernelEngine.Text.Native.ke_font_loader_handle* @out, ke_error** out_error);
}
