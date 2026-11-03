using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_signal_bus
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_signal_bus *, const char *, uint32_t, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, sbyte*, uint, uint*, KernelEngine.Result.Native.Result> signal_id;

    [NativeTypeName("bool (*)(struct ke_signal_bus *, const char *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, sbyte*, uint*, bool> signal_lookup;

    [NativeTypeName("ke_result (*)(struct ke_signal_bus *, ke_entity, uint32_t, ke_entity, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, global::KernelEngine.Ecs.Entity, uint, global::KernelEngine.Ecs.Entity, uint, KernelEngine.Result.Native.Result> connect;

    [NativeTypeName("bool (*)(struct ke_signal_bus *, ke_entity, uint32_t, ke_entity, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, global::KernelEngine.Ecs.Entity, uint, global::KernelEngine.Ecs.Entity, uint, bool> disconnect;

    [NativeTypeName("void (*)(struct ke_signal_bus *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, global::KernelEngine.Ecs.Entity, void> forget_entity;

    [NativeTypeName("ke_result (*)(struct ke_signal_bus *, ke_entity, uint32_t, const void *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, global::KernelEngine.Ecs.Entity, uint, void*, uint, KernelEngine.Result.Native.Result> emit;

    [NativeTypeName("const ke_signal_delivery *(*)(struct ke_signal_bus *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, uint*, SignalDelivery*> deliveries;

    [NativeTypeName("void (*)(struct ke_signal_bus *)")]
    public delegate* unmanaged[Cdecl]<ke_signal_bus*, void> clear_frame;
}
