using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_pass_ctx
{
    public void* handle;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render_pass_ctx *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_pass_ctx*, sbyte*, ke_texture_handle> get_texture;

    [NativeTypeName("void (*)(struct ke_render_pass_ctx *, uint32_t *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_render_pass_ctx*, uint*, uint*, void> get_backbuffer_size;

    [NativeTypeName("const struct ke_frame_packet *(*)(struct ke_render_pass_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_render_pass_ctx*, ke_frame_packet*> get_frame_packet;

    [NativeTypeName("struct ke_render *(*)(struct ke_render_pass_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_render_pass_ctx*, ke_render*> get_renderer;
}
