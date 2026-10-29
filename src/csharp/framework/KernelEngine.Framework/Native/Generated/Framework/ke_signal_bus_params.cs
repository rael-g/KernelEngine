using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public partial struct ke_signal_bus_params
{
    [NativeTypeName("uint32_t")]
    public uint max_signals;

    [NativeTypeName("uint32_t")]
    public uint max_connections;

    [NativeTypeName("uint32_t")]
    public uint max_events;

    [NativeTypeName("uint32_t")]
    public uint max_deliveries;

    [NativeTypeName("uint32_t")]
    public uint payload_capacity;
}
