using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_signal_bus_handle
{
    public ke_signal_bus* @ref;

    [NativeTypeName("void (*)(ke_signal_bus *)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, void> destroy;
}
