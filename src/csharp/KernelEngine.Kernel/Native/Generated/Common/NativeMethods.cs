using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_common", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_error_is", ExactSpelling = true)]
    public static extern bool error_is([NativeTypeName("const ke_error *")] ke_error* err, [NativeTypeName("const ke_error_type *")] ke_error_type* type);

    [DllImport("ke_common", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_error_set", ExactSpelling = true)]
    public static extern ke_result error_set(ke_error** out_error, [NativeTypeName("const ke_error_type *")] ke_error_type* type, [NativeTypeName("const char *")] sbyte* domain, [NativeTypeName("const char *")] sbyte* message);
}
