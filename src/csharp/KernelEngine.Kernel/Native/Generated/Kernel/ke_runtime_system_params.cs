namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_runtime_system_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public ke_phase phase;

    [NativeTypeName("const ke_component_access *")]
    public ke_component_access* access_list;

    [NativeTypeName("uint32_t")]
    public uint access_count;

    public bool exclusive;

    public void* user_data;

    [NativeTypeName("void (*)(ke_system_ctx *, void *, float)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, void*, float, void> execute;
}
