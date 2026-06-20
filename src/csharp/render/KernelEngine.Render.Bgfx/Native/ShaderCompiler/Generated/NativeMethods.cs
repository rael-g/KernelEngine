using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Bgfx.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_shader_compiler_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_shader_compiler_bgfx_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_shader_compiler_handle")]
    public static extern KernelEngine.Render.Native.ke_shader_compiler_handle shader_compiler_bgfx_create([NativeTypeName("const ke_shader_compiler_bgfx_params *")] ke_shader_compiler_bgfx_params* @params);
}
