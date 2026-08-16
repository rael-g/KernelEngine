using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_signal_bus
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_signal_bus *, const char *, uint32_t, uint32_t *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, sbyte*, uint, uint*, ke_error**, bool> signal_id;

    [NativeTypeName("bool (*)(struct ke_signal_bus *, const char *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, sbyte*, uint*, bool> signal_lookup;

    [NativeTypeName("bool (*)(struct ke_signal_bus *, ke_entity, uint32_t, ke_entity, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, ulong, uint, ulong, uint, ke_error**, bool> connect;

    [NativeTypeName("bool (*)(struct ke_signal_bus *, ke_entity, uint32_t, ke_entity, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, ulong, uint, ulong, uint, bool> disconnect;

    [NativeTypeName("void (*)(struct ke_signal_bus *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, ulong, void> forget_entity;

    [NativeTypeName("bool (*)(struct ke_signal_bus *, ke_entity, uint32_t, const void *, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, ulong, uint, void*, uint, ke_error**, bool> emit;

    [NativeTypeName("const ke_signal_delivery *(*)(struct ke_signal_bus *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, uint*, ke_signal_delivery*> deliveries;

    [NativeTypeName("void (*)(struct ke_signal_bus *)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, void> clear_frame;
}
