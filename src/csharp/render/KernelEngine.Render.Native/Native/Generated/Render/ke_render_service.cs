using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_service
{
    public void* handle;

    [NativeTypeName("ke_component_id (*)(struct ke_render_service *, const ke_render_resource_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_resource_params*, KernelEngine.Common.Native.ke_error**, uint> declare;

    [NativeTypeName("ke_component_id (*)(struct ke_render_service *, const char *, ke_gpu_texture, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ulong, KernelEngine.Common.Native.ke_error**, uint> import_texture;

    [NativeTypeName("ke_component_id (*)(struct ke_render_service *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, KernelEngine.Common.Native.ke_error**, uint> import_tag;

    [NativeTypeName("ke_component_id (*)(struct ke_render_service *, const char *, ke_gpu_buffer, uint64_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ulong, ulong, KernelEngine.Common.Native.ke_error**, uint> import_buffer;

    [NativeTypeName("ke_component_id (*)(struct ke_render_service *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, uint> cid;

    [NativeTypeName("struct ke_render_pass_ctx *(*)(struct ke_render_service *, const ke_render_pass_io *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_pass_io*, ke_render_pass_ctx*> begin_pass;

    [NativeTypeName("void (*)(struct ke_render_service *, struct ke_render_pass_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_pass_ctx*, void> end_pass;

    [NativeTypeName("bool (*)(struct ke_render_service *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, KernelEngine.Common.Native.ke_error**, bool> begin_frame;

    [NativeTypeName("bool (*)(struct ke_render_service *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, KernelEngine.Common.Native.ke_error**, bool> end_frame;

    [NativeTypeName("ke_mesh_handle (*)(struct ke_render_service *, const char *, const void *, size_t, const uint16_t *, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, void*, nuint, ushort*, uint, KernelEngine.Common.Native.ke_error**, ke_mesh_handle> upload_mesh;

    [NativeTypeName("bool (*)(struct ke_render_service *, ke_mesh_handle, ke_gpu_buffer *, ke_gpu_buffer *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_mesh_handle, ulong*, ulong*, uint*, bool> mesh_buffers;

    [NativeTypeName("void (*)(struct ke_render_service *, float, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, float, float, float, float, void> set_clear_color;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render_service *, const char *, uint32_t, uint32_t, const void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, uint, uint, void*, KernelEngine.Common.Native.ke_error**, ke_texture_handle> upload_texture;

    [NativeTypeName("ke_material_handle (*)(struct ke_render_service *, const char *, const float *, float, float, ke_texture_handle, ke_texture_handle, ke_alpha_mode, float, float, float, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, float*, float, float, ke_texture_handle, ke_texture_handle, ke_alpha_mode, float, float, float, sbyte*, KernelEngine.Common.Native.ke_error**, ke_material_handle> create_material;

    [NativeTypeName("ke_render_material_binding (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_material_handle, ulong> material_binding;

    [NativeTypeName("ke_alpha_mode (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_material_handle, ke_alpha_mode> material_alpha_mode;

    [NativeTypeName("float (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_material_handle, float> material_alpha_cutoff;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render_service *, const char *, uint32_t, const void *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, uint, void*, KernelEngine.Common.Native.ke_error**, ke_texture_handle> upload_cubemap;

    [NativeTypeName("ke_gpu_texture_view (*)(struct ke_render_service *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_texture_handle, ulong> texture_view;

    [NativeTypeName("ke_gpu_texture_view (*)(struct ke_render_service *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ulong> resource_view;

    [NativeTypeName("ke_gpu_texture (*)(struct ke_render_service *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ulong> resource_texture;

    [NativeTypeName("ke_gpu_buffer (*)(struct ke_render_service *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ulong> resource_buffer;

    [NativeTypeName("uint64_t (*)(struct ke_render_service *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ulong> resource_buffer_size;

    [NativeTypeName("void (*)(struct ke_render_service *, uint32_t *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, uint*, uint*, void> backbuffer_size;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_gpu_buffer, uint64_t, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ulong, ulong, void*, nuint, void> upload;

    [NativeTypeName("ke_gpu_pipeline (*)(struct ke_render_service *, const ke_gpu_render_pipeline_params *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_gpu_render_pipeline_params*, ulong> get_or_create_pipeline;

    [NativeTypeName("const char *(*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_material_handle, sbyte*> material_shader;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_mesh_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_mesh_handle, void> retain_mesh;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_mesh_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_mesh_handle, void> release_mesh;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_texture_handle, void> retain_texture;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_texture_handle, void> release_texture;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_material_handle, void> retain_material;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_material_handle, void> release_material;

    [NativeTypeName("bool (*)(struct ke_render_service *, const char *, ke_mesh_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ke_mesh_handle*, bool> try_get_mesh;

    [NativeTypeName("bool (*)(struct ke_render_service *, const char *, ke_texture_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ke_texture_handle*, bool> try_get_texture;

    [NativeTypeName("bool (*)(struct ke_render_service *, const char *, ke_material_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ke_material_handle*, bool> try_get_material;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_texture_handle> white_texture;

    [NativeTypeName("ke_gpu_shader_module (*)(struct ke_render_service *, const char *, ke_gpu_shader_stage, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, uint, KernelEngine.Common.Native.ke_error**, ulong> load_shader;

    [NativeTypeName("void (*)(struct ke_render_service *, const ke_render_frame_globals *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_frame_globals*, void> set_frame_globals;

    [NativeTypeName("const ke_render_frame_globals *(*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_frame_globals*> frame_globals;

    [NativeTypeName("void (*)(struct ke_render_service *, const ke_render_lighting *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_lighting*, void> set_lighting;

    [NativeTypeName("const ke_render_lighting *(*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_lighting*> lighting;

    [NativeTypeName("ke_render_resource_binder *(*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_resource_binder*> resource_binder;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_gpu_texture_format> backbuffer_format;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_render_service *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ke_gpu_texture_format> resource_format;

    [NativeTypeName("uint32_t (*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, uint> resource_generation;
}
