namespace KernelEngine.Kernel.Native;

public partial struct ke_render_graph
{
}

public unsafe partial struct ke_render_graph
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_render_graph *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const ke_resource_desc *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_resource_desc*, ke_result> declare_resource;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const char *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, sbyte*, ke_texture_handle, ke_result> import_texture;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const ke_render_pass_params *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_render_pass_params*, ke_result> add_pass;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, sbyte*, ke_result> remove_pass;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_result> compile;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const struct ke_frame_packet *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_frame_packet*, ke_result> execute;
}
