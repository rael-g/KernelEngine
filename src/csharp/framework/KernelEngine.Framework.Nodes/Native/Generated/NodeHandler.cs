using System.Numerics;

using global::KernelEngine.Common;
using global::KernelEngine.Ecs;
using global::KernelEngine.Physics;
using global::KernelEngine.Render;

using KernelEngine.Asset.Native;
using KernelEngine.Audio.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Framework.Nodes.Native;

public unsafe partial struct NodeHandler
{
    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId Event;

    [NativeTypeName("ke_node_behaviour_fn")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, void*, KernelEngine.Result.Native.Result> On;
}
