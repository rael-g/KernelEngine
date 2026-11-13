using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;

namespace KernelEngine.Audio.Native;

public unsafe partial struct ke_sound_module_config
{
    [NativeTypeName("const char *")]
    public sbyte* root;

    [NativeTypeName("ke_schedule_set_id")]
    public uint set;
}
