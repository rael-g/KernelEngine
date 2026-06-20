using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct ke_render
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_render *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_error**, bool> on_initialize;

    [NativeTypeName("bool (*)(struct ke_render *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_error**, bool> on_shutdown;

    [NativeTypeName("bool (*)(struct ke_render *, ke_bool, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, byte, ke_error**, bool> set_orthographic;

    [NativeTypeName("bool (*)(struct ke_render *, float, float, float, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, float, float, float, float, ke_error**, bool> clear_color;

    [NativeTypeName("bool (*)(struct ke_render *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_error**, bool> frame;

    [NativeTypeName("bool (*)(struct ke_render *, const ke_mat4 *, const ke_mat4 *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_mat4*, ke_mat4*, ke_error**, bool> set_view_transform;

    [NativeTypeName("ke_ndc_convention (*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_ndc_convention> get_ndc_convention;

    [NativeTypeName("ke_mesh_handle (*)(struct ke_render *, const ke_vertex *, uint32_t, const uint16_t *, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_vertex*, uint, ushort*, uint, ke_error**, ke_mesh_handle> create_mesh;

    [NativeTypeName("bool (*)(struct ke_render *, ke_mesh_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_mesh_handle, ke_error**, bool> destroy_mesh;

    [NativeTypeName("ke_material_handle (*)(struct ke_render *, const ke_material *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_material*, ke_error**, ke_material_handle> create_material;

    [NativeTypeName("bool (*)(struct ke_render *, ke_material_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_material_handle, ke_error**, bool> destroy_material;

    [NativeTypeName("bool (*)(struct ke_render *, ke_mesh_handle, ke_material_handle, const ke_mat4 *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_mesh_handle, ke_material_handle, ke_mat4*, ke_error**, bool> submit_mesh;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render *, uint32_t, uint32_t, const uint8_t *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, uint, uint, byte*, ke_error**, ke_texture_handle> create_texture_rgba;

    [NativeTypeName("bool (*)(struct ke_render *, ke_texture_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_texture_handle, ke_error**, bool> destroy_texture;

    [NativeTypeName("bool (*)(struct ke_render *, const ke_directional_light *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_directional_light*, ke_error**, bool> set_directional_light;

    [NativeTypeName("bool (*)(struct ke_render *, float, float, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, float, float, float, ke_error**, bool> set_ambient_light;

    [NativeTypeName("bool (*)(struct ke_render *, float, float, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, float, float, float, ke_error**, bool> set_camera_pos;

    [NativeTypeName("ke_texture_handle (*)(struct ke_render *, uint32_t, const uint8_t *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, uint, byte*, ke_error**, ke_texture_handle> create_cubemap_rgba;

    [NativeTypeName("bool (*)(struct ke_render *, ke_texture_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_texture_handle, ke_error**, bool> submit_skybox;

    [NativeTypeName("ke_shadow_map_handle (*)(struct ke_render *, uint32_t, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, uint, uint, ke_error**, ke_shadow_map_handle> create_shadow_map;

    [NativeTypeName("bool (*)(struct ke_render *, ke_shadow_map_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_shadow_map_handle, ke_error**, bool> destroy_shadow_map;

    [NativeTypeName("bool (*)(struct ke_render *, ke_shadow_map_handle, const ke_mat4 *, const ke_mat4 *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_shadow_map_handle, ke_mat4*, ke_mat4*, ke_error**, bool> begin_shadow_pass;

    [NativeTypeName("bool (*)(struct ke_render *, ke_mesh_handle, const ke_mat4 *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_mesh_handle, ke_mat4*, ke_error**, bool> submit_mesh_shadow;

    [NativeTypeName("bool (*)(struct ke_render *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_error**, bool> end_shadow_pass;

    [NativeTypeName("bool (*)(struct ke_render *, ke_shadow_map_handle, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_shadow_map_handle, ke_error**, bool> set_shadow_map;

    [NativeTypeName("bool (*)(struct ke_render *, ke_bool, float, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, byte, float, float, ke_error**, bool> set_tonemapping;

    [NativeTypeName("bool (*)(struct ke_render *, ke_bool, float, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, byte, float, float, ke_error**, bool> set_bloom;

    [NativeTypeName("bool (*)(struct ke_render *, const ke_point_light *, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_point_light*, uint, ke_error**, bool> set_point_lights;

    [NativeTypeName("bool (*)(struct ke_render *, const ke_spot_light *, uint32_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_spot_light*, uint, ke_error**, bool> set_spot_lights;

    [NativeTypeName("bool (*)(struct ke_render *, ke_bool, float, float, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, byte, float, float, float, ke_error**, bool> set_ssao;

    [NativeTypeName("bool (*)(struct ke_render *, const ke_cluster_config *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_cluster_config*, ke_error**, bool> set_cluster_config;

    [NativeTypeName("bool (*)(struct ke_render *, ke_texture_handle, float, float, float, float, float, float, float, float, float, float, float, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_texture_handle, float, float, float, float, float, float, float, float, float, float, float, float, ke_error**, bool> submit_ui_quad;

    [NativeTypeName("bool (*)(struct ke_render *, const struct ke_frame_packet *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_frame_packet*, ke_error**, bool> submit_packet;

    [NativeTypeName("const char *(*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, sbyte*> get_last_fatal_error;

    [NativeTypeName("ke_render_graph_handle (*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_render_graph_handle> create_render_graph;

    [NativeTypeName("struct ke_render_graph *(*)(struct ke_render *)")]
    public delegate* unmanaged[Cdecl]<ke_render*, ke_render_graph*> get_render_graph;
}
