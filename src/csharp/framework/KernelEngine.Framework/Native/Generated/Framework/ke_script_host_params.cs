using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public partial struct ke_script_host_params
{
    [NativeTypeName("uint32_t")]
    public uint max_types;
}
