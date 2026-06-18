namespace KernelEngine.Kernel.Native;

public partial struct ke_render_graph
{
}

public unsafe partial struct ke_render_graph
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const ke_resource_desc *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_resource_desc*, ke_error**, ke_result> declare_resource;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const char *, ke_texture_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, sbyte*, ke_texture_handle, ke_error**, ke_result> import_texture;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const ke_render_pass_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_render_pass_params*, ke_error**, ke_result> add_pass;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, sbyte*, ke_error**, ke_result> remove_pass;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_error**, ke_result> compile;

    [NativeTypeName("ke_result (*)(struct ke_render_graph *, const struct ke_frame_packet *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_frame_packet*, ke_error**, ke_result> execute;
}
