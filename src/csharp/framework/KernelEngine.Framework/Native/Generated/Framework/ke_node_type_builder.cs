using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_node_type_builder
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_node_type_builder *, const char *, ke_variant_type)")]
    public delegate* unmanaged[Cdecl]<ke_node_type_builder*, sbyte*, KernelEngine.Ecs.Native.ke_variant_type, bool> field;

    [NativeTypeName("ke_node_hook_id (*)(struct ke_node_type_builder *, ke_node_hook_kind, ke_node_hook_fn, void *)")]
    public delegate* unmanaged[Cdecl]<ke_node_type_builder*, ke_node_hook_kind, delegate* unmanaged[Cdecl]<void*, ulong*, void**, nuint, float, void>, void*, uint> hook;

    [NativeTypeName("bool (*)(struct ke_node_type_builder *, ke_node_hook_id, const char *, ke_access)")]
    public delegate* unmanaged[Cdecl]<ke_node_type_builder*, uint, sbyte*, KernelEngine.Runtime.Native.ke_access, bool> access;
}
