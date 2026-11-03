using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.FileSystem.Std.Native;

public unsafe partial struct ke_file_system_std_params
{
    [NativeTypeName("const char *")]
    public sbyte* root;
}
