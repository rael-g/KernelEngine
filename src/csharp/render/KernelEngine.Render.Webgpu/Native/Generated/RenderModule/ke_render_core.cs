using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_core
{
    public void* handle;

    [NativeTypeName("ke_component_id (*)(struct ke_render_core *, const ke_render_resource_desc *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_render_resource_desc*, ke_error**, uint> declare;

    [NativeTypeName("ke_component_id (*)(struct ke_render_core *, const char *, ke_gpu_texture, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong, ke_error**, uint> import_texture;

    [NativeTypeName("ke_component_id (*)(struct ke_render_core *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, uint> cid;

    [NativeTypeName("struct ke_render_pass_ctx *(*)(struct ke_render_core *, ke_system_ctx *, const ke_render_pass_io *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_system_ctx*, ke_render_pass_io*, ke_render_pass_ctx*> begin_pass;

    [NativeTypeName("void (*)(struct ke_render_core *, struct ke_render_pass_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_render_pass_ctx*, void> end_pass;

    [NativeTypeName("ke_bool (*)(struct ke_render_core *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_error**, byte> begin_frame;

    [NativeTypeName("ke_bool (*)(struct ke_render_core *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_error**, byte> end_frame;

    [NativeTypeName("ke_mesh_handle (*)(struct ke_render_core *, const void *, size_t, const uint16_t *, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, void*, nuint, ushort*, uint, ke_error**, ke_mesh_handle> upload_mesh;

    [NativeTypeName("ke_bool (*)(struct ke_render_core *, ke_mesh_handle, ke_gpu_buffer *, ke_gpu_buffer *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_mesh_handle, ulong*, ulong*, uint*, byte> mesh_buffers;

    [NativeTypeName("void (*)(struct ke_render_core *, float, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, float, float, float, float, void> set_clear_color;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render_core *, uint32_t, uint32_t, const void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, uint, uint, void*, ke_error**, ke_texture_handle> upload_texture;

    [NativeTypeName("ke_material_handle (*)(struct ke_render_core *, const float *, float, float, ke_texture_handle, ke_texture_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, float*, float, float, ke_texture_handle, ke_texture_handle, ke_error**, ke_material_handle> create_material;

    [NativeTypeName("ke_gpu_bind_group_layout (*)(struct ke_render_core *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ulong> material_layout;

    [NativeTypeName("ke_gpu_bind_group (*)(struct ke_render_core *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_material_handle, ulong> material_bind_group;
}
