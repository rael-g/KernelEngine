#ifndef KERNEL_ENGINE_KERNEL_WORLD_COMPONENTS_H_
#define KERNEL_ENGINE_KERNEL_WORLD_COMPONENTS_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/common/math.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint64_t ke_entity;

    // ── Transform ───────────────────────────────────────────────────────────

    typedef struct ke_transform_component
    {
        ke_vec3 position;
        ke_quat rotation;
        ke_vec3 scale;
        ke_mat4 world_matrix;
    } ke_transform_component;

    // ── Hierarchy ───────────────────────────────────────────────────────────

    typedef struct ke_hierarchy_component
    {
        ke_entity parent;
        ke_entity first_child;
        ke_entity next_sibling;
        ke_entity prev_sibling;
    } ke_hierarchy_component;

    // ── Name ────────────────────────────────────────────────────────────────

    typedef struct ke_name_component
    {
        char name[64];
    } ke_name_component;

    // ── Mesh ────────────────────────────────────────────────────────────────

    typedef struct ke_mesh_component
    {
        uint32_t mesh_handle;
        uint32_t material_handle;
    } ke_mesh_component;

    // ── Skybox ──────────────────────────────────────────────────────────────

    typedef struct ke_skybox_component
    {
        uint32_t cubemap_handle;
    } ke_skybox_component;

    // ── Camera ──────────────────────────────────────────────────────────────

    typedef struct ke_camera_component
    {
        float fov;
        float near_z;
        float far_z;
        bool  orthographic;
    } ke_camera_component;

    // ── Lighting ────────────────────────────────────────────────────────────

    typedef struct ke_light_component
    {
        float dir_x, dir_y, dir_z;
        float r, g, b, intensity;
    } ke_light_component;

    typedef struct ke_point_light_component
    {
        float radius;
        float r, g, b, intensity;
    } ke_point_light_component;

    typedef struct ke_spot_light_component
    {
        float range;
        float dir_x, dir_y, dir_z;
        float inner_angle;
        float outer_angle;
        float r, g, b, intensity;
    } ke_spot_light_component;

    // ── Scripting ───────────────────────────────────────────────────────────

    typedef ke_result (*ke_script_func)(ke_entity entity);
    typedef ke_result (*ke_script_update_func)(ke_entity entity, float dt);

    typedef struct ke_script_component
    {
        bool started;
        ke_script_func on_start;
        ke_script_update_func on_update;
    } ke_script_component;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_COMPONENTS_H_
