using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;

namespace KernelEngine.Module.Native;

public unsafe partial struct ke_module_targets
{
    [NativeTypeName("ke_schedule *")]
    public KernelEngine.Schedule.Native.ke_schedule* startup;

    [NativeTypeName("ke_schedule *")]
    public KernelEngine.Schedule.Native.ke_schedule* pre_update;

    [NativeTypeName("ke_schedule *")]
    public KernelEngine.Schedule.Native.ke_schedule* @fixed;

    [NativeTypeName("ke_schedule *")]
    public KernelEngine.Schedule.Native.ke_schedule* update;

    [NativeTypeName("ke_schedule *")]
    public KernelEngine.Schedule.Native.ke_schedule* shutdown;

    [NativeTypeName("ke_schedule_set_id")]
    public uint startup_set;

    [NativeTypeName("ke_schedule_set_id")]
    public uint pre_update_set;

    [NativeTypeName("ke_schedule_set_id")]
    public uint fixed_pre_update_set;

    [NativeTypeName("ke_schedule_set_id")]
    public uint fixed_update_set;

    [NativeTypeName("ke_schedule_set_id")]
    public uint fixed_post_update_set;

    [NativeTypeName("ke_schedule_set_id")]
    public uint update_set;

    [NativeTypeName("ke_schedule_set_id")]
    public uint post_update_set;

    [NativeTypeName("ke_schedule_set_id")]
    public uint shutdown_set;
}
