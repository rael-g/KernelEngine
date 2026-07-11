using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_core
{
    public void* handle;

    [NativeTypeName("ke_component_id (*)(struct ke_render_core *, const ke_render_resource_desc *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_render_resource_desc*, ke_error**, uint> declare;

    [NativeTypeName("ke_component_id (*)(struct ke_render_core *, const char *, ke_gpu_texture, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong, ke_error**, uint> import_texture;

    [NativeTypeName("ke_component_id (*)(struct ke_render_core *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ke_error**, uint> import_tag;

    [NativeTypeName("ke_component_id (*)(struct ke_render_core *, const char *, ke_gpu_buffer, uint64_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong, ulong, ke_error**, uint> import_buffer;

    [NativeTypeName("ke_component_id (*)(struct ke_render_core *, const char *, ke_gpu_bind_group, ke_gpu_bind_group_layout, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong, ulong, ke_error**, uint> import_bind_group;

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

    [NativeTypeName("ke_mesh_handle (*)(struct ke_render_core *, const char *, const void *, size_t, const uint16_t *, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, void*, nuint, ushort*, uint, ke_error**, ke_mesh_handle> upload_mesh;

    [NativeTypeName("ke_bool (*)(struct ke_render_core *, ke_mesh_handle, ke_gpu_buffer *, ke_gpu_buffer *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_mesh_handle, ulong*, ulong*, uint*, byte> mesh_buffers;

    [NativeTypeName("void (*)(struct ke_render_core *, float, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, float, float, float, float, void> set_clear_color;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render_core *, const char *, uint32_t, uint32_t, const void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, uint, uint, void*, ke_error**, ke_texture_handle> upload_texture;

    [NativeTypeName("ke_material_handle (*)(struct ke_render_core *, const char *, const float *, float, float, ke_texture_handle, ke_texture_handle, ke_alpha_mode, float, float, float, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, float*, float, float, ke_texture_handle, ke_texture_handle, ke_alpha_mode, float, float, float, uint, ke_error**, ke_material_handle> create_material;

    [NativeTypeName("ke_gpu_bind_group_layout (*)(struct ke_render_core *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ulong> material_layout;

    [NativeTypeName("ke_gpu_bind_group (*)(struct ke_render_core *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_material_handle, ulong> material_bind_group;

    [NativeTypeName("ke_alpha_mode (*)(struct ke_render_core *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_material_handle, ke_alpha_mode> material_alpha_mode;

    [NativeTypeName("float (*)(struct ke_render_core *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_material_handle, float> material_alpha_cutoff;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render_core *, const char *, uint32_t, const void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, uint, void*, ke_error**, ke_texture_handle> upload_cubemap;

    [NativeTypeName("ke_gpu_texture_view (*)(struct ke_render_core *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_texture_handle, ulong> texture_view;

    [NativeTypeName("ke_gpu_sampler (*)(struct ke_render_core *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ulong> sampler;

    [NativeTypeName("ke_gpu_texture_view (*)(struct ke_render_core *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong> resource_view;

    [NativeTypeName("ke_gpu_texture (*)(struct ke_render_core *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong> resource_texture;

    [NativeTypeName("ke_gpu_buffer (*)(struct ke_render_core *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong> resource_buffer;

    [NativeTypeName("uint64_t (*)(struct ke_render_core *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong> resource_buffer_size;

    [NativeTypeName("ke_gpu_bind_group (*)(struct ke_render_core *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong> resource_bind_group;

    [NativeTypeName("ke_gpu_bind_group_layout (*)(struct ke_render_core *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ulong> resource_bind_group_layout;

    [NativeTypeName("void (*)(struct ke_render_core *, ke_gpu_buffer, uint64_t, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ulong, ulong, void*, nuint, void> upload;

    [NativeTypeName("ke_gpu_pipeline (*)(struct ke_render_core *, const ke_gpu_render_pipeline_params *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_gpu_render_pipeline_params*, ulong> get_or_create_pipeline;

    [NativeTypeName("uint32_t (*)(struct ke_render_core *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_material_handle, uint> material_shader_variant;

    [NativeTypeName("void (*)(struct ke_render_core *, ke_mesh_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_mesh_handle, void> retain_mesh;

    [NativeTypeName("void (*)(struct ke_render_core *, ke_mesh_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_mesh_handle, void> release_mesh;

    [NativeTypeName("void (*)(struct ke_render_core *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_texture_handle, void> retain_texture;

    [NativeTypeName("void (*)(struct ke_render_core *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_texture_handle, void> release_texture;

    [NativeTypeName("void (*)(struct ke_render_core *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_material_handle, void> retain_material;

    [NativeTypeName("void (*)(struct ke_render_core *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_material_handle, void> release_material;

    [NativeTypeName("ke_bool (*)(struct ke_render_core *, const char *, ke_mesh_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ke_mesh_handle*, byte> try_get_mesh;

    [NativeTypeName("ke_bool (*)(struct ke_render_core *, const char *, ke_texture_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ke_texture_handle*, byte> try_get_texture;

    [NativeTypeName("ke_bool (*)(struct ke_render_core *, const char *, ke_material_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, sbyte*, ke_material_handle*, byte> try_get_material;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render_core *)")]
    public delegate* unmanaged[Cdecl]<ke_render_core*, ke_texture_handle> white_texture;
}
