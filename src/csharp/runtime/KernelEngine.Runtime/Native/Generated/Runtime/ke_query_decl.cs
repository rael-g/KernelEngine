using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_query_decl
{
    [NativeTypeName("const ke_component_access *")]
    public ke_component_access* terms;

    [NativeTypeName("uint32_t")]
    public uint term_count;
}
