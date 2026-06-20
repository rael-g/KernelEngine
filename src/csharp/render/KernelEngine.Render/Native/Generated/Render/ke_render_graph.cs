using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_graph
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_render_graph *, const ke_resource_desc *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_resource_desc*, ke_error**, bool> declare_resource;

    [NativeTypeName("bool (*)(struct ke_render_graph *, const char *, ke_texture_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, sbyte*, ke_texture_handle, ke_error**, bool> import_texture;

    [NativeTypeName("bool (*)(struct ke_render_graph *, const ke_render_pass_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_render_pass_params*, ke_error**, bool> add_pass;

    [NativeTypeName("bool (*)(struct ke_render_graph *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, sbyte*, ke_error**, bool> remove_pass;

    [NativeTypeName("bool (*)(struct ke_render_graph *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_error**, bool> compile;

    [NativeTypeName("bool (*)(struct ke_render_graph *, const struct ke_frame_packet *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_graph*, ke_frame_packet*, ke_error**, bool> execute;
}
