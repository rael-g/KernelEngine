using System.Numerics;

using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Io.Native;

public unsafe partial struct ke_io_handle
{
    public ke_io* @ref;

    [NativeTypeName("void (*)(ke_io *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, void> destroy;
}
