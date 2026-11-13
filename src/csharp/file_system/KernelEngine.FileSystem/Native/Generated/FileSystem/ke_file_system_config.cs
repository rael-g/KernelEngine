using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.FileSystem.Native;

public unsafe partial struct ke_file_system_config
{
    [NativeTypeName("const char *")]
    public sbyte* root;
}
