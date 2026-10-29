using KernelEngine.Result.Native;

namespace KernelEngine.FileSystem.Native;

[NativeTypeName("unsigned int")]
public enum ke_file_kind : uint
{
    KE_FILE_KIND_FILE = 1,
    KE_FILE_KIND_DIRECTORY = 2,
    KE_FILE_KIND_OTHER = 3,
}
