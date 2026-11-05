using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public partial struct SignalBusParams
{
    [NativeTypeName("uint32_t")]
    public uint MaxSignals;

    [NativeTypeName("uint32_t")]
    public uint MaxConnections;

    [NativeTypeName("uint32_t")]
    public uint MaxEvents;

    [NativeTypeName("uint32_t")]
    public uint MaxDeliveries;

    [NativeTypeName("uint32_t")]
    public uint PayloadCapacity;
}
