using KernelEngine.Common.Native;

namespace KernelEngine.Configuration.Native;

public unsafe partial struct ke_configuration_source
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_configuration_source *, ke_configuration *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_configuration_source*, ke_configuration*, sbyte*, KernelEngine.Common.Native.ke_error**, bool> load;
}
