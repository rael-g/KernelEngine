using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Input.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_create", ExactSpelling = true)]
    public static extern ke_input_handle input_create([NativeTypeName("struct ke_logger *")] KernelEngine.Logger.Native.ke_logger* logger, ke_error** out_error);
}
