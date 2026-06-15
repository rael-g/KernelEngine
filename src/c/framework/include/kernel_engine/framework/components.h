#ifndef KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_
#define KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_

#include <kernel_engine/spatial/transform.h>
#include <kernel_engine/render/handles.h>
#include <kernel_engine/ecs/ecs.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_hierarchy_component
    {
        ke_entity parent;
        ke_entity first_child;
        ke_entity next_sibling;
        ke_entity prev_sibling;
    } ke_hierarchy_component;

    typedef struct ke_name_component
    {
        char name[64];
    } ke_name_component;

#define KE_COMPONENT_NAME_HIERARCHY "hierarchy"
#define KE_COMPONENT_NAME_NAME      "name"

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
    } ke_directional_light_component;

    typedef struct ke_point_light_component
    {
        float radius;
        float r, g, b;
        float intensity;
    } ke_point_light_component;

    typedef struct ke_spot_light_component
    {
        float dir_x, dir_y, dir_z;
        float inner_angle;
        float outer_angle;
        float range;
        float r, g, b;
        float intensity;
    } ke_spot_light_component;

    typedef struct ke_mesh_component
    {
        ke_mesh_handle     mesh;
        ke_material_handle material;
        char               primitive[32];
        float              color[4];
    } ke_mesh_component;

#define KE_COMPONENT_NAME_CAMERA            "camera"
#define KE_COMPONENT_NAME_DIRECTIONAL_LIGHT "directional_light"
#define KE_COMPONENT_NAME_POINT_LIGHT       "point_light"
#define KE_COMPONENT_NAME_SPOT_LIGHT        "spot_light"
#define KE_COMPONENT_NAME_MESH              "mesh"

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_COMPONENTS_H_
