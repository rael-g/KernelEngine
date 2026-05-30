namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_render_pass_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public ke_pass_type type;

    [NativeTypeName("const ke_resource_ref *")]
    public ke_resource_ref* reads;

    [NativeTypeName("uint32_t")]
    public uint reads_count;

    [NativeTypeName("const ke_resource_ref *")]
    public ke_resource_ref* writes;

    [NativeTypeName("uint32_t")]
    public uint writes_count;

    [NativeTypeName("ke_render_pass_record_fn")]
    public delegate* unmanaged[Cdecl]<ke_render_pass_ctx*, void*, void> record;

    public void* user;
}
