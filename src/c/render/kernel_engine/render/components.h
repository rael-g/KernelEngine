#ifndef KERNEL_ENGINE_RENDER_COMPONENTS_H_
#define KERNEL_ENGINE_RENDER_COMPONENTS_H_

#include <kernel_engine/render/handles.h>
#include <kernel_engine/spatial/transform.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_camera_component
    {
        float   fov;
        float   near_plane;
        float   far_plane;
        float   orthographic_size;
        uint8_t orthographic;
    } ke_camera_component;

    typedef struct ke_directional_light_component
    {
        float dir_x, dir_y, dir_z;
        float r, g, b;
        float intensity;
        float ambient_r, ambient_g, ambient_b;
    } ke_directional_light_component;

    typedef struct ke_point_light_component
    {
        float r, g, b;
        float intensity;
        float radius;
    } ke_point_light_component;

    typedef struct ke_spot_light_component
    {
        float dir_x, dir_y, dir_z;
        float r, g, b;
        float intensity;
        float range;
        float inner_angle;
        float outer_angle;
    } ke_spot_light_component;

    /// Scene-wide ambient color. The first entity carrying it wins.
    typedef struct ke_ambient_light_component
    {
        float r, g, b;
    } ke_ambient_light_component;

    /// Environment cubemap driving both the skybox and image-based lighting.
    typedef struct ke_skybox_component
    {
        ke_texture_handle cubemap;
    } ke_skybox_component;

    typedef struct ke_mesh_component
    {
        ke_mesh_handle     mesh;
        ke_material_handle material;
        char               primitive[32];
    } ke_mesh_component;

#define KE_COMPONENT_NAME_CAMERA            "camera"
#define KE_COMPONENT_NAME_DIRECTIONAL_LIGHT "directional_light"
#define KE_COMPONENT_NAME_POINT_LIGHT       "point_light"
#define KE_COMPONENT_NAME_SPOT_LIGHT        "spot_light"
#define KE_COMPONENT_NAME_AMBIENT_LIGHT     "ambient_light"
#define KE_COMPONENT_NAME_SKYBOX            "skybox"
#define KE_COMPONENT_NAME_MESH              "mesh"

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_COMPONENTS_H_
