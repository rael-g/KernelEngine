using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Framework.Nodes.Native;

public unsafe partial struct ke_node_with
{
    [NativeTypeName("const ke_component_desc *")]
    public KernelEngine.Ecs.Native.ke_component_desc* component;

    [NativeTypeName("const void *")]
    public void* initial;

    [NativeTypeName("size_t")]
    public nuint initial_size;
}
