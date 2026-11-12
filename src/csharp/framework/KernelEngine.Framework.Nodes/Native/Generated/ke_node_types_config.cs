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
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Framework.Nodes.Native;

public partial struct ke_node_types_config
{
    [NativeTypeName("ke_set_id")]
    public uint pre_update;

    [NativeTypeName("ke_set_id")]
    public uint update;

    [NativeTypeName("ke_set_id")]
    public uint fixed_update;

    [NativeTypeName("ke_set_id")]
    public uint post_update;
}
