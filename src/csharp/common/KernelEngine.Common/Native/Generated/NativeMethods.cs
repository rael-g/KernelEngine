using System;
using System.Runtime.InteropServices;

namespace KernelEngine.Common.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_common", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_error_last", ExactSpelling = true)]
    [return: NativeTypeName("const ke_error *")]
    public static extern ke_error* error_last();

    [DllImport("ke_common", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_error_fatal", ExactSpelling = true)]
    public static extern void error_fatal([NativeTypeName("const ke_error *")] ke_error* err);

    [NativeTypeName("#define KE_RESOURCE_HANDLE_NONE UINT32_MAX")]
    public const uint KE_RESOURCE_HANDLE_NONE = (4294967295U);

    [NativeTypeName("#define KE_COMPONENT_NAME_TRANSFORM \"transform\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_TRANSFORM => "transform"u8;
}
