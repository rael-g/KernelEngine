using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Configuration.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_configuration_toml", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_configuration_toml_load", ExactSpelling = true)]
    public static extern bool configuration_toml_load([NativeTypeName("ke_configuration *")] KernelEngine.Configuration.Native.ke_configuration* cfg, [NativeTypeName("const char *")] sbyte* path, ke_error** out_error);
}
