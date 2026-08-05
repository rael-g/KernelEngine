using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_node_host
{
    public void* handle;

    [NativeTypeName("ke_node_type_builder *(*)(struct ke_node_host *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_node_host*, sbyte*, ke_error**, ke_node_type_builder*> begin_type;

    [NativeTypeName("bool (*)(struct ke_node_host *, ke_node_type_builder *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_node_host*, ke_node_type_builder*, ke_error**, bool> commit;

    [NativeTypeName("ke_entity (*)(struct ke_node_host *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_node_host*, sbyte*, ke_error**, ulong> spawn;

    [NativeTypeName("bool (*)(struct ke_node_host *, ke_entity, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_node_host*, ulong, sbyte*, ke_error**, bool> attach;

    [NativeTypeName("bool (*)(struct ke_node_host *, const char *, const ke_variant_table **, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_node_host*, sbyte*, KernelEngine.Ecs.Native.ke_variant_table**, ke_error**, bool> describe;
}
