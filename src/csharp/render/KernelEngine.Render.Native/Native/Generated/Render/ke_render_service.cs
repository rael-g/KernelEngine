using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_service
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, const ke_render_resource_params *, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_resource_params*, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> declare;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, const char *, ke_gpu_texture, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ulong, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> import_texture;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, const char *, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> import_tag;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, const char *, ke_gpu_buffer, uint64_t, ke_component_id *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, ulong, ulong, global::KernelEngine.Ecs.ComponentId*, KernelEngine.Result.Native.Result> import_buffer;

    [NativeTypeName("ke_component_id (*)(struct ke_render_service *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, global::KernelEngine.Ecs.ComponentId> cid;

    [NativeTypeName("struct ke_render_pass_ctx *(*)(struct ke_render_service *, const ke_render_pass_io *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, RenderPassIo*, ke_render_pass_ctx*> begin_pass;

    [NativeTypeName("void (*)(struct ke_render_service *, struct ke_render_pass_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_pass_ctx*, void> end_pass;

    [NativeTypeName("ke_result (*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, KernelEngine.Result.Native.Result> begin_frame;

    [NativeTypeName("ke_result (*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, KernelEngine.Result.Native.Result> end_frame;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, const char *, const void *, size_t, const uint16_t *, uint32_t, ke_mesh_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, void*, nuint, ushort*, uint, global::KernelEngine.Render.MeshHandle*, KernelEngine.Result.Native.Result> upload_mesh;

    [NativeTypeName("bool (*)(struct ke_render_service *, ke_mesh_handle, ke_gpu_buffer *, ke_gpu_buffer *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.MeshHandle, ulong*, ulong*, uint*, bool> mesh_buffers;

    [NativeTypeName("void (*)(struct ke_render_service *, float, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, float, float, float, float, void> set_clear_color;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, const char *, uint32_t, uint32_t, const uint8_t *, size_t, ke_texture_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, uint, uint, byte*, nuint, global::KernelEngine.Render.TextureHandle*, KernelEngine.Result.Native.Result> upload_texture;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, const char *, const float *, float, float, ke_texture_handle, ke_texture_handle, ke_alpha_mode, float, float, float, const char *, ke_material_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, float*, float, float, global::KernelEngine.Render.TextureHandle, global::KernelEngine.Render.TextureHandle, global::KernelEngine.Render.AlphaMode, float, float, float, sbyte*, global::KernelEngine.Render.MaterialHandle*, KernelEngine.Result.Native.Result> create_material;

    [NativeTypeName("ke_render_material_binding (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.MaterialHandle, ulong> material_binding;

    [NativeTypeName("ke_alpha_mode (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.MaterialHandle, global::KernelEngine.Render.AlphaMode> material_alpha_mode;

    [NativeTypeName("float (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.MaterialHandle, float> material_alpha_cutoff;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, const char *, uint32_t, const uint8_t *, size_t, ke_texture_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, uint, byte*, nuint, global::KernelEngine.Render.TextureHandle*, KernelEngine.Result.Native.Result> upload_cubemap;

    [NativeTypeName("ke_gpu_texture_view (*)(struct ke_render_service *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.TextureHandle, ulong> texture_view;

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
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.MaterialHandle, sbyte*> material_shader;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_mesh_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.MeshHandle, void> retain_mesh;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_mesh_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.MeshHandle, void> release_mesh;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.TextureHandle, void> retain_texture;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.TextureHandle, void> release_texture;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.MaterialHandle, void> retain_material;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.MaterialHandle, void> release_material;

    [NativeTypeName("bool (*)(struct ke_render_service *, const char *, ke_mesh_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, global::KernelEngine.Render.MeshHandle*, bool> try_get_mesh;

    [NativeTypeName("bool (*)(struct ke_render_service *, const char *, ke_texture_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, global::KernelEngine.Render.TextureHandle*, bool> try_get_texture;

    [NativeTypeName("bool (*)(struct ke_render_service *, const char *, ke_material_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, global::KernelEngine.Render.MaterialHandle*, bool> try_get_material;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.TextureHandle> white_texture;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, const char *, ke_gpu_shader_stage, ke_gpu_shader_module *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, uint, ulong*, KernelEngine.Result.Native.Result> load_shader;

    [NativeTypeName("void (*)(struct ke_render_service *, const ke_render_frame_globals *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.RenderFrameGlobals*, void> set_frame_globals;

    [NativeTypeName("const ke_render_frame_globals *(*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.RenderFrameGlobals*> frame_globals;

    [NativeTypeName("void (*)(struct ke_render_service *, const ke_render_lighting *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.RenderLighting*, void> set_lighting;

    [NativeTypeName("const ke_render_lighting *(*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.RenderLighting*> lighting;

    [NativeTypeName("ke_render_resource_binder *(*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, ke_render_resource_binder*> resource_binder;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.GpuTextureFormat> backbuffer_format;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_render_service *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, sbyte*, global::KernelEngine.Render.GpuTextureFormat> resource_format;

    [NativeTypeName("uint32_t (*)(struct ke_render_service *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, uint> resource_generation;

    [NativeTypeName("ke_result (*)(struct ke_render_service *, ke_render_stage, ke_render_chain_mode, ke_render_chain_link *)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.RenderStage, global::KernelEngine.Render.RenderChainMode, uint*, KernelEngine.Result.Native.Result> join_chain;

    [NativeTypeName("void (*)(struct ke_render_service *, ke_render_chain_link)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, uint, void> leave_chain;

    [NativeTypeName("ke_gpu_texture_format (*)(struct ke_render_service *, ke_render_stage)")]
    public delegate* unmanaged[Cdecl]<ke_render_service*, global::KernelEngine.Render.RenderStage, global::KernelEngine.Render.GpuTextureFormat> chain_format;
}
