using KernelEngine.Asset.Native;
using KernelEngine.Common.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public partial struct ke_script_host_params
{
    [NativeTypeName("uint32_t")]
    public uint max_types;
}
