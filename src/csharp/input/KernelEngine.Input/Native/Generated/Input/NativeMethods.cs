using System.Runtime.InteropServices;

using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;

namespace KernelEngine.Input.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_create", ExactSpelling = true)]
    public static extern ke_input_handle input_create([NativeTypeName("struct ke_logger *")] KernelEngine.Logger.Native.ke_logger* logger, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_input_default", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_default_set_log_callback", ExactSpelling = true)]
    public static extern void input_default_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
