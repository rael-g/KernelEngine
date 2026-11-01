using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

public unsafe partial struct ke_configuration_source
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_configuration_source *, ke_configuration *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_configuration_source*, ke_configuration*, sbyte*, KernelEngine.Result.Native.Result> load;
}
