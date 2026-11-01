using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.FileSystem.Native;

public partial struct FileStat
{
    [NativeTypeName("ke_file_kind")]
    public FileKind Kind;

    [NativeTypeName("uint64_t")]
    public ulong Size;
}
