using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_signal_bus_handle
{
    public ke_signal_bus* @ref;

    [NativeTypeName("void (*)(ke_signal_bus *)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, void> destroy;
}
