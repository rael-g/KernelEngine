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
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_resource_desc*, int> declare_resource;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const char *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, sbyte*, ke_texture_handle, int> import_texture;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const ke_render_pass_params *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_render_pass_params*, int> add_pass;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, sbyte*, int> remove_pass;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, int> compile;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const struct ke_frame_packet *)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_frame_packet*, int> execute;
}
