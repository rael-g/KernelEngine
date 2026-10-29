using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

public unsafe partial struct ke_configuration_toml_params
{
    [NativeTypeName("ke_io *")]
    public KernelEngine.Io.Native.ke_io* io;
}
