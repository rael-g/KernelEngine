namespace KernelEngine.Core.Native;

public unsafe partial struct ke_system
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_system *)")]
    public delegate* unmanaged[Cdecl]<ke_system*, void> destroy;

    [NativeTypeName("ke_system_id")]
    public ulong numeric_id;

    [NativeTypeName("ke_result (*)(struct ke_system *)")]
    public delegate* unmanaged[Cdecl]<ke_system*, ke_result> on_initialize;

    [NativeTypeName("ke_result (*)(struct ke_system *)")]
    public delegate* unmanaged[Cdecl]<ke_system*, ke_result> on_shutdown;

    [NativeTypeName("ke_result (*)(struct ke_system *, const struct ke_frame *)")]
    public delegate* unmanaged[Cdecl]<ke_system*, ke_frame*, ke_result> on_update;
}
