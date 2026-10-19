using KernelEngine.Common.Native;

namespace KernelEngine.Configuration.Native;

public unsafe partial struct ke_configuration_source_handle
{
    public ke_configuration_source* @ref;

    [NativeTypeName("void (*)(ke_configuration_source *)")]
    public delegate* unmanaged[Cdecl]<ke_configuration_source*, void> destroy;
}
