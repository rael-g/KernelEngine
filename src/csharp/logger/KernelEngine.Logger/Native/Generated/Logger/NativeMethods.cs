using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Logger.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_logger_simple", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_log_level_to_string", ExactSpelling = true)]
    [return: NativeTypeName("const char *")]
    public static extern sbyte* log_level_to_string([NativeTypeName("int32_t")] int level);

    [DllImport("ke_logger_simple", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_logger_create", ExactSpelling = true)]
    public static extern ke_logger_handle logger_create(ke_error** out_error);
}
