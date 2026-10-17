using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Configuration.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_configuration_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_toml_create", ExactSpelling = true)]
    public static extern ke_configuration_source_handle configuration_toml_create([NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
