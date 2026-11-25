using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.FileSystem.Native;

[NativeTypeName("unsigned int")]
public enum FileKind : uint
{
    File = 1,
    Directory = 2,
    Other = 3,
}
