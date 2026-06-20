using KernelEngine.Common.Native;

namespace KernelEngine.Logger.Native;

public unsafe partial struct ke_logger_handle
{
    public ke_logger* @ref;

    [NativeTypeName("void (*)(ke_logger *)")]
    public delegate* unmanaged[Cdecl]<ke_logger*, void> destroy;
}
