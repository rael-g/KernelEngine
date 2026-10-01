using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_runtime_system_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public ke_phase phase;

    public void* user_data;

    [NativeTypeName("ke_system_execute_fn")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, void*, float, KernelEngine.Common.Native.ke_error**, bool> execute;

    [NativeTypeName("const ke_component_access *")]
    public ke_component_access* query_terms;

    [NativeTypeName("uint32_t")]
    public uint query_term_count;

    [NativeTypeName("const uint32_t *")]
    public uint* query_widths;

    [NativeTypeName("uint32_t")]
    public uint query_count;

    [NativeTypeName("const ke_component_access *")]
    public ke_component_access* access_list;

    [NativeTypeName("uint32_t")]
    public uint access_count;

    [NativeTypeName("uint32_t")]
    public uint pinned_thread;

    public bool per_entity;
}
