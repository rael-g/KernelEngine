using KernelEngine.Common.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime.Native;

public partial struct ke_component_access
{
    [NativeTypeName("ke_component_id")]
    public uint cid;

    public ke_access access;
}
