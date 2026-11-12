using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public partial struct ke_scene_tree_config
{
    [NativeTypeName("ke_set_id")]
    public uint set;
}
