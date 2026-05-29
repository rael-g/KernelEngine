using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Text.StbTrueType.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_text_stb_truetype", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_font_stb_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result font_stb_create([NativeTypeName("const ke_font_stb_params *")] ke_font_stb_params* @params, [NativeTypeName("ke_font **")] KernelEngine.Kernel.Native.ke_font** @out);
}
