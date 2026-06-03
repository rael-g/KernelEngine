namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_resource_queue
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_resource_queue *, const ke_resource_command *, ke_resource_future **)")]
    public delegate* unmanaged[Cdecl]<ke_resource_queue*, ke_resource_command*, ke_resource_future**, ke_result> submit;

    [NativeTypeName("uint32_t (*)(struct ke_resource_queue *, struct ke_render *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_resource_queue*, ke_render*, uint, uint> drain;

    [NativeTypeName("void (*)(struct ke_resource_queue *)")]
    public delegate* unmanaged[Cdecl]<ke_resource_queue*, void> destroy;
}
