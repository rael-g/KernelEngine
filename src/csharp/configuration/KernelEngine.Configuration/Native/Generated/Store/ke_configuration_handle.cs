using KernelEngine.Common.Native;

namespace KernelEngine.Configuration.Native;

public unsafe partial struct ke_configuration_handle
{
    public ke_configuration* @ref;

    [NativeTypeName("void (*)(ke_configuration *)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, void> destroy;
}
