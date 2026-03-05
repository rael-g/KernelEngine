namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_scene
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_scene *)")]
    public delegate* unmanaged[Cdecl]<ke_scene*, void> destroy;

    [NativeTypeName("struct ke_node *(*)(struct ke_scene *)")]
    public delegate* unmanaged[Cdecl]<ke_scene*, ke_node*> get_root;

    [NativeTypeName("ke_result (*)(struct ke_scene *, const ke_node_descriptor *, struct ke_node **)")]
    public delegate* unmanaged[Cdecl]<ke_scene*, ke_node_descriptor*, ke_node**, ke_result> create_node;

    [NativeTypeName("ke_result (*)(struct ke_scene *, struct ke_node *)")]
    public delegate* unmanaged[Cdecl]<ke_scene*, ke_node*, ke_result> destroy_node;

    [NativeTypeName("void (*)(struct ke_scene *)")]
    public delegate* unmanaged[Cdecl]<ke_scene*, void> update;
}
