using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Io.Native;

public unsafe partial struct ke_io_dir_entry
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("ke_file_kind")]
    public KernelEngine.FileSystem.Native.ke_file_kind kind;
}
