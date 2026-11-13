using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Module.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Audio.Native;

public unsafe partial struct ke_sound_config
{
    [NativeTypeName("const char *")]
    public sbyte* root;
}
