using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Io.Native;

public unsafe partial struct ke_io_result
{
    [NativeTypeName("ke_open_file *")]
    public KernelEngine.FileSystem.Native.ke_open_file* file;

    public void* bytes;

    [NativeTypeName("uint64_t")]
    public ulong size;

    [NativeTypeName("ke_file_stat")]
    public KernelEngine.FileSystem.Native.ke_file_stat stat;
}
