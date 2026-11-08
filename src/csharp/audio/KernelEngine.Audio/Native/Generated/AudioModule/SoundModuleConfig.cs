using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Audio.Native;

public unsafe partial struct SoundModuleConfig
{
    [NativeTypeName("const char *")]
    public sbyte* Root;
}
