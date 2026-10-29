using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_signal_delivery
{
    [NativeTypeName("ke_entity")]
    public ulong source;

    [NativeTypeName("ke_entity")]
    public ulong target;

    [NativeTypeName("uint32_t")]
    public uint signal_id;

    [NativeTypeName("uint32_t")]
    public uint handler_id;

    [NativeTypeName("const void *")]
    public void* payload;

    [NativeTypeName("uint32_t")]
    public uint payload_size;
}
