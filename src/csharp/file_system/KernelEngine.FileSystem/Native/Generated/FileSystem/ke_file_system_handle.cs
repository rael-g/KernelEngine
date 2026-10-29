using KernelEngine.Result.Native;

namespace KernelEngine.FileSystem.Native;

public unsafe partial struct ke_file_system_handle
{
    public ke_file_system* @ref;

    [NativeTypeName("void (*)(ke_file_system *)")]
    public delegate* unmanaged[Cdecl]<ke_file_system*, void> destroy;
}
