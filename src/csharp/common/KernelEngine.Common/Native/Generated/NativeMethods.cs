using System;
using System.Runtime.InteropServices;

namespace KernelEngine.Common.Native;

public static unsafe partial class NativeMethods
{
    [NativeTypeName("#define KE_RESOURCE_HANDLE_NONE UINT32_MAX")]
    public const uint KE_RESOURCE_HANDLE_NONE = 0xffffffffU;

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_set_current_name", ExactSpelling = true)]
    public static extern void thread_set_current_name([NativeTypeName("const char *")] sbyte* name);

    [DllImport("ke_threading", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_get_current_name", ExactSpelling = true)]
    [return: NativeTypeName("const char *")]
    public static extern sbyte* thread_get_current_name();

    [NativeTypeName("#define KE_COMPONENT_NAME_TRANSFORM \"transform\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_TRANSFORM => "transform"u8;
}
