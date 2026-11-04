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

public unsafe partial struct ke_component_registry
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_component_registry *, ke_component_id, const ke_component_field *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_component_registry*, global::KernelEngine.Ecs.ComponentId, KernelEngine.Ecs.Native.ComponentField*, uint, KernelEngine.Result.Native.Result> register_component_fields;

    [NativeTypeName("const ke_component_field *(*)(struct ke_component_registry *, ke_component_id, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_component_registry*, global::KernelEngine.Ecs.ComponentId, uint*, KernelEngine.Ecs.Native.ComponentField*> get_component_fields;

    [NativeTypeName("ke_result (*)(struct ke_component_registry *, ke_component_id, ke_component_apply_fn, void *)")]
    public delegate* unmanaged[Cdecl]<ke_component_registry*, global::KernelEngine.Ecs.ComponentId, delegate* unmanaged[Cdecl]<void*, void*, KernelEngine.Ecs.Native.VariantTableEntry*, uint, KernelEngine.Result.Native.Result>, void*, KernelEngine.Result.Native.Result> register_component_apply;

    [NativeTypeName("ke_component_apply_fn (*)(struct ke_component_registry *, ke_component_id, void **)")]
    public delegate* unmanaged[Cdecl]<ke_component_registry*, global::KernelEngine.Ecs.ComponentId, void**, delegate* unmanaged[Cdecl]<void*, void*, KernelEngine.Ecs.Native.VariantTableEntry*, uint, KernelEngine.Result.Native.Result>> get_component_apply;

    [NativeTypeName("ke_result (*)(struct ke_component_registry *, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_component_registry*, sbyte*, sbyte*, KernelEngine.Result.Native.Result> register_component_alias;

    [NativeTypeName("ke_result (*)(struct ke_component_registry *, const char *, ke_component_meta *)")]
    public delegate* unmanaged[Cdecl]<ke_component_registry*, sbyte*, KernelEngine.Ecs.Native.ComponentMeta*, KernelEngine.Result.Native.Result> resolve_component;
}
