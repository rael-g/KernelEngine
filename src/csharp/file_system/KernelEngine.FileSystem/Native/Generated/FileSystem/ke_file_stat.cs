using KernelEngine.Result.Native;

namespace KernelEngine.FileSystem.Native;

public partial struct ke_file_stat
{
    public ke_file_kind kind;

    [NativeTypeName("uint64_t")]
    public ulong size;
}
