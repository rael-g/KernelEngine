using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

[NativeTypeName("unsigned int")]
public enum ke_config_type : uint
{
    KE_CONFIG_INT,
    KE_CONFIG_FLOAT,
    KE_CONFIG_DOUBLE,
    KE_CONFIG_BOOL,
    KE_CONFIG_STRING,
}
