using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render_resource_binder
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_render_resource_binder *, const ke_render_shader_binding *)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ke_render_shader_binding*, KernelEngine.Result.Native.ke_result> provide;

    [NativeTypeName("ke_result (*)(struct ke_render_resource_binder *, const ke_render_shader_layout_params *, ke_render_shader_layout *)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ke_render_shader_layout_params*, ulong*, KernelEngine.Result.Native.ke_result> create_shader_layout;

    [NativeTypeName("void (*)(struct ke_render_resource_binder *, ke_render_shader_layout)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ulong, void> destroy_shader_layout;

    [NativeTypeName("ke_result (*)(struct ke_render_resource_binder *, ke_render_shader_layout, ke_gpu_bind_group_layout *, uint32_t, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ulong, ulong*, uint, uint*, KernelEngine.Result.Native.ke_result> pipeline_layouts;

    [NativeTypeName("ke_result (*)(struct ke_render_resource_binder *, ke_render_shader_layout, const char *, const char *, const ke_render_shader_binding *, uint32_t, ke_render_resource_set *)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ulong, sbyte*, sbyte*, ke_render_shader_binding*, uint, ulong*, KernelEngine.Result.Native.ke_result> create_set;

    [NativeTypeName("void (*)(struct ke_render_resource_binder *, ke_render_resource_set)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ulong, void> destroy_set;

    [NativeTypeName("void (*)(struct ke_render_resource_binder *, struct ke_gpu_render_pass *, ke_render_resource_set, const uint32_t *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ke_gpu_render_pass*, ulong, uint*, uint, void> bind_render_set;

    [NativeTypeName("void (*)(struct ke_render_resource_binder *, struct ke_gpu_compute_pass *, ke_render_resource_set, const uint32_t *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ke_gpu_compute_pass*, ulong, uint*, uint, void> bind_compute_set;

    [NativeTypeName("ke_result (*)(struct ke_render_resource_binder *, const ke_render_material_data *, ke_render_material_binding *)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ke_render_material_data*, ulong*, KernelEngine.Result.Native.ke_result> create_material;

    [NativeTypeName("void (*)(struct ke_render_resource_binder *, ke_render_material_binding)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ulong, void> destroy_material;

    [NativeTypeName("void (*)(struct ke_render_resource_binder *, struct ke_gpu_render_pass *, ke_render_shader_layout, ke_render_material_binding)")]
    public delegate* unmanaged[Cdecl]<ke_render_resource_binder*, ke_gpu_render_pass*, ulong, ulong, void> bind_material;
}
