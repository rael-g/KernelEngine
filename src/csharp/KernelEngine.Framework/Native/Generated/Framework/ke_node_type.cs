namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_node_type
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public void* ctx;

    [NativeTypeName("ke_node_create_func")]
    public delegate* unmanaged[Cdecl]<void*, ulong, sbyte*, ke_result> create;

    [NativeTypeName("ke_node_set_property_func")]
    public delegate* unmanaged[Cdecl]<void*, ulong, sbyte*, ke_variant, ke_result> set_property;
}
