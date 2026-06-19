using System.Runtime.InteropServices;

namespace KernelEngine.Logger.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_logger_simple", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_logger_create", ExactSpelling = true)]
    public static extern ke_result logger_create(ke_logger_handle* out_logger, ke_error** out_error);
}
