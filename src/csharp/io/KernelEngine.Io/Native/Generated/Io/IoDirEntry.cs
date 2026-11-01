using System.Numerics;

using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Io.Native;

public unsafe partial struct IoDirEntry
{
    [NativeTypeName("const char *")]
    public sbyte* Name;

    [NativeTypeName("ke_file_kind")]
    public KernelEngine.FileSystem.Native.FileKind Kind;
}
