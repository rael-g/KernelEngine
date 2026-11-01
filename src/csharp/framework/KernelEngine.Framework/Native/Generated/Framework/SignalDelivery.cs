using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct SignalDelivery
{
    [NativeTypeName("ke_entity")]
    public global::KernelEngine.Ecs.Entity Source;

    [NativeTypeName("ke_entity")]
    public global::KernelEngine.Ecs.Entity Target;

    [NativeTypeName("uint32_t")]
    public uint SignalId;

    [NativeTypeName("uint32_t")]
    public uint HandlerId;

    [NativeTypeName("const void *")]
    public void* Payload;

    [NativeTypeName("uint32_t")]
    public uint PayloadSize;
}
