using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Configuration.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_configuration", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_create", ExactSpelling = true)]
    public static extern ke_configuration_handle configuration_create([NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
