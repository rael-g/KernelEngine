using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Bgfx.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_shader_compiler_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_shader_compiler_bgfx_create", ExactSpelling = true)]
    public static extern ke_result shader_compiler_bgfx_create([NativeTypeName("const ke_shader_compiler_bgfx_params *")] ke_shader_compiler_bgfx_params* @params, [NativeTypeName("ke_shader_compiler_handle *")] KernelEngine.Render.Native.ke_shader_compiler_handle* out_compiler);
}
