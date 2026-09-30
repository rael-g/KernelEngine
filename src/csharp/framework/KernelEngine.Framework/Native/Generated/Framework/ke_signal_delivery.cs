using KernelEngine.Common.Native;

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
