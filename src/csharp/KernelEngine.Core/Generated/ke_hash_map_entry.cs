namespace KernelEngine.Core.Native;

public unsafe partial struct ke_hash_map_entry
{
    [NativeTypeName("uint64_t")]
    public ulong key;

    public void* value;
}
