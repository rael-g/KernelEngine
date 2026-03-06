namespace KernelEngine.Kernel.Native;

public partial struct ke_hierarchy_component
{
    [NativeTypeName("uint64_t")]
    public ulong parent;

    [NativeTypeName("uint64_t")]
    public ulong first_child;

    [NativeTypeName("uint64_t")]
    public ulong next_sibling;

    [NativeTypeName("uint64_t")]
    public ulong prev_sibling;
}
