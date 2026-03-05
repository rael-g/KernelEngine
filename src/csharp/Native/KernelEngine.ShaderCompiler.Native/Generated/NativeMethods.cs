using KernelEngine.Kernel.Native;
using System;
using System.Runtime.InteropServices;

namespace KernelEngine.ShaderCompiler.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_shader_compiler_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_shader_compiler_bgfx_create", ExactSpelling = true)]
    public static extern ke_result shader_compiler_bgfx_create([NativeTypeName("const ke_shader_compiler_bgfx_descriptor *")] ke_shader_compiler_bgfx_descriptor* desc, ke_shader_compiler** out_compiler);

    [NativeTypeName("#define KE_ID_SHADER_COMPILER \"ke_shader_compiler\"")]
    public static ReadOnlySpan<byte> KE_ID_SHADER_COMPILER => "ke_shader_compiler"u8;
}
