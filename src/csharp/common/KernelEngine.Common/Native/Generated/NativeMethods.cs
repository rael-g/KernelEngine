using System.Runtime.InteropServices;

namespace KernelEngine.Common.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_common", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_error_is", ExactSpelling = true)]
    public static extern bool error_is([NativeTypeName("const ke_error *")] ke_error* err, [NativeTypeName("const ke_error_type *")] ke_error_type* type);

    [DllImport("ke_common", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_error_last", ExactSpelling = true)]
    [return: NativeTypeName("const ke_error *")]
    public static extern ke_error* error_last();

    [DllImport("ke_common", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_error_set", ExactSpelling = true)]
    public static extern void error_set(ke_error** out_error, [NativeTypeName("const ke_error_type *")] ke_error_type* type, [NativeTypeName("const char *")] sbyte* message, [NativeTypeName("const char *")] sbyte* file, [NativeTypeName("uint32_t")] uint line, [NativeTypeName("const ke_error *")] ke_error* cause);

    [DllImport("ke_common", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_error_fatal", ExactSpelling = true)]
    public static extern void error_fatal([NativeTypeName("const ke_error *")] ke_error* err);

    [DllImport("ke_common", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_resource_cache_create", ExactSpelling = true)]
    public static extern ke_resource_cache_handle resource_cache_create([NativeTypeName("const ke_resource_cache_params *")] ke_resource_cache_params* @params, ke_error** out_error);

    [NativeTypeName("#define KE_RESOURCE_HANDLE_NONE UINT32_MAX")]
    public const uint KE_RESOURCE_HANDLE_NONE = (4294967295U);
}
