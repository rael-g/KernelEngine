namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_render
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, int> on_initialize;

    [NativeTypeName("ke_result (*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, int> on_shutdown;

    [NativeTypeName("ke_result (*)(struct ke_render *, bool)")]
    public delegate* unmanaged[Cdecl]<ke_render*, bool, int> set_orthographic;

    [NativeTypeName("ke_result (*)(struct ke_render *, float, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render*, float, float, float, float, int> clear_color;

    [NativeTypeName("ke_result (*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, int> frame;

    [NativeTypeName("ke_result (*)(struct ke_render *, const ke_mat4 *, const ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_mat4*, ke_mat4*, int> set_view_transform;

    [NativeTypeName("ke_ndc_convention (*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_ndc_convention> get_ndc_convention;

    [NativeTypeName("ke_result (*)(struct ke_render *, const ke_vertex *, uint32_t, const uint16_t *, uint32_t, ke_mesh_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_vertex*, uint, ushort*, uint, ke_mesh_handle*, int> create_mesh;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_mesh_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_mesh_handle, int> destroy_mesh;

    [NativeTypeName("ke_result (*)(struct ke_render *, const ke_material *, ke_material_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_material*, ke_material_handle*, int> create_material;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_material_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_material_handle, int> destroy_material;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_mesh_handle, ke_material_handle, const ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_mesh_handle, ke_material_handle, ke_mat4*, int> submit_mesh;

    [NativeTypeName("ke_result (*)(struct ke_render *, uint32_t, uint32_t, const uint8_t *, ke_texture_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, uint, uint, byte*, ke_texture_handle*, int> create_texture_rgba;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_texture_handle, int> destroy_texture;

    [NativeTypeName("ke_result (*)(struct ke_render *, const ke_directional_light *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_directional_light*, int> set_directional_light;

    [NativeTypeName("ke_result (*)(struct ke_render *, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render*, float, float, float, int> set_ambient_light;

    [NativeTypeName("ke_result (*)(struct ke_render *, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render*, float, float, float, int> set_camera_pos;

    [NativeTypeName("ke_result (*)(struct ke_render *, uint32_t, const uint8_t *, ke_texture_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, uint, byte*, ke_texture_handle*, int> create_cubemap_rgba;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_texture_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_texture_handle, int> submit_skybox;

    [NativeTypeName("ke_result (*)(struct ke_render *, uint32_t, uint32_t, ke_shadow_map_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, uint, uint, ke_shadow_map_handle*, int> create_shadow_map;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_shadow_map_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_shadow_map_handle, int> destroy_shadow_map;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_shadow_map_handle, const ke_mat4 *, const ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_shadow_map_handle, ke_mat4*, ke_mat4*, int> begin_shadow_pass;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_mesh_handle, const ke_mat4 *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_mesh_handle, ke_mat4*, int> submit_mesh_shadow;

    [NativeTypeName("ke_result (*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, int> end_shadow_pass;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_shadow_map_handle)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_shadow_map_handle, int> set_shadow_map;

    [NativeTypeName("ke_result (*)(struct ke_render *, bool, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render*, bool, float, float, int> set_tonemapping;

    [NativeTypeName("ke_result (*)(struct ke_render *, bool, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render*, bool, float, float, int> set_bloom;

    [NativeTypeName("ke_result (*)(struct ke_render *, const ke_point_light *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_point_light*, uint, int> set_point_lights;

    [NativeTypeName("ke_result (*)(struct ke_render *, const ke_spot_light *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_spot_light*, uint, int> set_spot_lights;

    [NativeTypeName("ke_result (*)(struct ke_render *, bool, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render*, bool, float, float, float, int> set_ssao;

    [NativeTypeName("ke_result (*)(struct ke_render *, const ke_cluster_config *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_cluster_config*, int> set_cluster_config;

    [NativeTypeName("ke_result (*)(struct ke_render *, ke_texture_handle, float, float, float, float, float, float, float, float, float, float, float, float)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_texture_handle, float, float, float, float, float, float, float, float, float, float, float, float, int> submit_ui_quad;

    [NativeTypeName("ke_result (*)(struct ke_render *, const struct ke_frame_packet *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_frame_packet*, int> submit_packet;

    [NativeTypeName("const char *(*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, sbyte*> get_last_fatal_error;

    [NativeTypeName("struct ke_render_graph *(*)(struct ke_render *, struct ke_allocator *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_allocator*, ke_render_graph*> create_render_graph;

    [NativeTypeName("struct ke_render_graph *(*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_render_graph*> get_render_graph;
}
