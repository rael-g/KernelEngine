using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Configuration.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_configuration_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_toml_load", ExactSpelling = true)]
    public static extern bool configuration_toml_load(ke_configuration* cfg, [NativeTypeName("const char *")] sbyte* path, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
