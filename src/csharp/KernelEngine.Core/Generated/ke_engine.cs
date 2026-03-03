namespace KernelEngine.Core.Native;

public unsafe partial struct ke_engine
{
    public void* handle;

    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;

    [NativeTypeName("void (*)(struct ke_engine *)")]
    public delegate* unmanaged[Cdecl]<ke_engine*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_engine *)")]
    public delegate* unmanaged[Cdecl]<ke_engine*, ke_result> initialize;

    [NativeTypeName("ke_result (*)(struct ke_engine *, const struct ke_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_engine*, ke_frame*, ke_result> tick;

    [NativeTypeName("ke_result (*)(struct ke_engine *)")]
    public delegate* unmanaged[Cdecl]<ke_engine*, ke_result> shutdown;

    [NativeTypeName("ke_result (*)(struct ke_engine *, struct ke_system *)")]
    public delegate* unmanaged[Cdecl]<ke_engine*, ke_system*, ke_result> register_system;
}
