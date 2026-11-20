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

public unsafe partial struct ke_node_component
{
    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId component;

    [NativeTypeName("const void *")]
    public void* data;

    [NativeTypeName("size_t")]
    public nuint size;
}
