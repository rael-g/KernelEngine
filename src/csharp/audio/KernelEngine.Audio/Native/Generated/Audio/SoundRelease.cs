using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.Audio.Native;

[NativeTypeName("unsigned int")]
public enum SoundRelease : uint
{
    Keep = 0,
    WhenDone = 1,
}
