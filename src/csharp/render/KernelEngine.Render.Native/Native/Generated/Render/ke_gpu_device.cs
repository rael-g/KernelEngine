using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_device
{
    public void* handle;

    [NativeTypeName("ke_gpu_queue (*)(struct ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong> get_default_queue;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_queue, ke_gpu_command_buffer *const *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, ke_gpu_command_buffer**, uint, void> queue_submit;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_queue)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> queue_poll;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_queue)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> queue_wait_idle;

    [NativeTypeName("ke_gpu_buffer (*)(struct ke_gpu_device *, const ke_gpu_buffer_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_buffer_params*, KernelEngine.Common.Native.ke_error**, ulong> create_buffer;

    [NativeTypeName("ke_gpu_texture (*)(struct ke_gpu_device *, const ke_gpu_texture_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_texture_params*, KernelEngine.Common.Native.ke_error**, ulong> create_texture;

    [NativeTypeName("ke_gpu_texture_view (*)(struct ke_gpu_device *, ke_gpu_texture, const ke_gpu_texture_view_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, ke_gpu_texture_view_params*, KernelEngine.Common.Native.ke_error**, ulong> create_texture_view;

    [NativeTypeName("ke_gpu_sampler (*)(struct ke_gpu_device *, const ke_gpu_sampler_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_sampler_params*, KernelEngine.Common.Native.ke_error**, ulong> create_sampler;

    [NativeTypeName("ke_gpu_shader_module (*)(struct ke_gpu_device *, const ke_gpu_shader_module_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_shader_module_params*, KernelEngine.Common.Native.ke_error**, ulong> create_shader_module;

    [NativeTypeName("ke_gpu_pipeline (*)(struct ke_gpu_device *, const ke_gpu_render_pipeline_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_render_pipeline_params*, KernelEngine.Common.Native.ke_error**, ulong> create_render_pipeline;

    [NativeTypeName("ke_gpu_pipeline (*)(struct ke_gpu_device *, const ke_gpu_compute_pipeline_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_compute_pipeline_params*, KernelEngine.Common.Native.ke_error**, ulong> create_compute_pipeline;

    [NativeTypeName("ke_gpu_bind_group_layout (*)(struct ke_gpu_device *, const ke_gpu_bind_group_layout_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_bind_group_layout_params*, KernelEngine.Common.Native.ke_error**, ulong> create_bind_group_layout;

    [NativeTypeName("ke_gpu_bind_group (*)(struct ke_gpu_device *, const ke_gpu_bind_group_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_bind_group_params*, KernelEngine.Common.Native.ke_error**, ulong> create_bind_group;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_buffer)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_buffer;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_texture)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_texture;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_texture_view)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_texture_view;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_sampler)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_sampler;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_shader_module)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_shader_module;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_pipeline)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_pipeline;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_bind_group_layout)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_bind_group_layout;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_bind_group)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_bind_group;

    [NativeTypeName("ke_gpu_command_encoder_handle (*)(struct ke_gpu_device *, const ke_gpu_command_encoder_params *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_command_encoder_params*, KernelEngine.Common.Native.ke_error**, ke_gpu_command_encoder_handle> create_command_encoder;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_buffer, uint64_t, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, ulong, void*, nuint, void> write_buffer;

    [NativeTypeName("void *(*)(struct ke_gpu_device *, ke_gpu_buffer, size_t, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, nuint, nuint, void*> map_buffer;

    [NativeTypeName("void *(*)(struct ke_gpu_device *, ke_gpu_buffer, size_t, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, nuint, nuint, void*> map_buffer_write;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_buffer)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> unmap_buffer;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_capabilities *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_capabilities*, void> get_capabilities;

    [NativeTypeName("const void *(*)(struct ke_gpu_device *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, sbyte*, void*> query_extension;

    [NativeTypeName("ke_gpu_shader_language (*)(struct ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_shader_language> shader_language;

    [NativeTypeName("ke_ndc_convention (*)(struct ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_ndc_convention> get_ndc_convention;

    [NativeTypeName("void (*)(struct ke_gpu_device *, const ke_gpu_render_pipeline_params *, void (*)(ke_gpu_pipeline, void *), void *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_render_pipeline_params*, delegate* unmanaged[Cdecl]<ulong, void*, void>, void*, void> create_render_pipeline_async;

    [NativeTypeName("void (*)(struct ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, void> flush_pipeline_compiles;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_buffer, size_t, size_t, void (*)(ke_gpu_buffer, bool, void *), void *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, nuint, nuint, delegate* unmanaged[Cdecl]<ulong, bool, void*, void>, void*, void> map_buffer_read;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_pipeline)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_compute_pipeline;
}
