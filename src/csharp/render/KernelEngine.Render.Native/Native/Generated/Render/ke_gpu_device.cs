using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_gpu_device
{
    public void* handle;

    [NativeTypeName("ke_gpu_queue (*)(struct ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong> get_default_queue;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_queue, ke_gpu_command_buffer *const *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, GpuCommandBuffer**, uint, void> queue_submit;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_queue)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> queue_poll;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_queue)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> queue_wait_idle;

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, const ke_gpu_buffer_params *, ke_gpu_buffer *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_buffer_params*, ulong*, KernelEngine.Result.Native.Result> create_buffer;

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, const ke_gpu_texture_params *, ke_gpu_texture *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_texture_params*, ulong*, KernelEngine.Result.Native.Result> create_texture;

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, ke_gpu_texture, const ke_gpu_texture_view_params *, ke_gpu_texture_view *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, ke_gpu_texture_view_params*, ulong*, KernelEngine.Result.Native.Result> create_texture_view;

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, const ke_gpu_sampler_params *, ke_gpu_sampler *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_sampler_params*, ulong*, KernelEngine.Result.Native.Result> create_sampler;

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, const ke_gpu_shader_module_params *, ke_gpu_shader_module *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_shader_module_params*, ulong*, KernelEngine.Result.Native.Result> create_shader_module;

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, const ke_gpu_render_pipeline_params *, ke_gpu_pipeline *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_render_pipeline_params*, ulong*, KernelEngine.Result.Native.Result> create_render_pipeline;

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, const ke_gpu_compute_pipeline_params *, ke_gpu_pipeline *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_compute_pipeline_params*, ulong*, KernelEngine.Result.Native.Result> create_compute_pipeline;

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, const ke_gpu_bind_group_layout_params *, ke_gpu_bind_group_layout *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_bind_group_layout_params*, ulong*, KernelEngine.Result.Native.Result> create_bind_group_layout;

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, const ke_gpu_bind_group_params *, ke_gpu_bind_group *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_bind_group_params*, ulong*, KernelEngine.Result.Native.Result> create_bind_group;

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

    [NativeTypeName("ke_result (*)(struct ke_gpu_device *, const ke_gpu_command_encoder_params *, ke_gpu_command_encoder_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_command_encoder_params*, ke_gpu_command_encoder_handle*, KernelEngine.Result.Native.Result> create_command_encoder;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_buffer, uint64_t, const void *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, ulong, void*, nuint, void> write_buffer;

    [NativeTypeName("void *(*)(struct ke_gpu_device *, ke_gpu_buffer, size_t, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, nuint, nuint, void*> map_buffer;

    [NativeTypeName("void *(*)(struct ke_gpu_device *, ke_gpu_buffer, size_t, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, nuint, nuint, void*> map_buffer_write;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_buffer)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> unmap_buffer;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_capabilities *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, global::KernelEngine.Render.GpuCapabilities*, void> get_capabilities;

    [NativeTypeName("const void *(*)(struct ke_gpu_device *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, sbyte*, void*> query_extension;

    [NativeTypeName("ke_gpu_shader_language (*)(struct ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, global::KernelEngine.Render.GpuShaderLanguage> shader_language;

    [NativeTypeName("ke_ndc_convention (*)(struct ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, global::KernelEngine.Render.NdcConvention> get_ndc_convention;

    [NativeTypeName("void (*)(struct ke_gpu_device *, const ke_gpu_render_pipeline_params *, ke_gpu_pipeline_ready_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ke_gpu_render_pipeline_params*, delegate* unmanaged[Cdecl]<ulong, void*, void>, void*, void> create_render_pipeline_async;

    [NativeTypeName("void (*)(struct ke_gpu_device *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, void> flush_pipeline_compiles;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_buffer, size_t, size_t, ke_gpu_buffer_mapped_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, nuint, nuint, delegate* unmanaged[Cdecl]<ulong, bool, void*, void>, void*, void> map_buffer_read;

    [NativeTypeName("void (*)(struct ke_gpu_device *, ke_gpu_pipeline)")]
    public delegate* unmanaged[Cdecl]<ke_gpu_device*, ulong, void> destroy_compute_pipeline;
}
