namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_node_type_registry
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_node_type_registry *, const ke_node_type *)")]
    public delegate* unmanaged[Cdecl]<ke_node_type_registry*, ke_node_type*, ke_result> register_type;

    [NativeTypeName("ke_result (*)(struct ke_node_type_registry *, const char *, const ke_node_type **)")]
    public delegate* unmanaged[Cdecl]<ke_node_type_registry*, sbyte*, ke_node_type**, ke_result> lookup;

    [NativeTypeName("void (*)(struct ke_node_type_registry *)")]
    public delegate* unmanaged[Cdecl]<ke_node_type_registry*, void> destroy;
}
