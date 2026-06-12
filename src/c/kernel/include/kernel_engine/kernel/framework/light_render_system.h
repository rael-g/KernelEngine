#ifndef KERNEL_ENGINE_FRAMEWORK_LIGHT_RENDER_SYSTEM_H_
#define KERNEL_ENGINE_FRAMEWORK_LIGHT_RENDER_SYSTEM_H_

// ke_light_render_system — native port of C# LightRenderSystem.
//
// Owns three component cids: directional (LightComponent), point, spot.
// On every tick:
//   * first directional light becomes packet->dir_light (has_dir_light = true);
//   * every point light, with position fetched from TransformComponent.position,
//     is appended to packet->point_lights until capacity;
//   * every spot light, same position rule, is appended to packet->spot_lights.

#include <kernel_engine/kernel/framework/framework_export.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/world/system.h>

struct ke_world;

#ifdef __cplusplus
extern "C"
{
#endif

    /// Mirrors KernelEngine.Framework.LightComponent (directional).
    typedef struct ke_directional_light_component
    {
        float dir_x, dir_y, dir_z;
        float r, g, b;
        float intensity;
    } ke_directional_light_component;

    /// Mirrors KernelEngine.Framework.PointLightComponent.
    typedef struct ke_point_light_component
    {
        float radius;
        float r, g, b;
        float intensity;
    } ke_point_light_component;

    /// Mirrors KernelEngine.Framework.SpotLightComponent.
    typedef struct ke_spot_light_component
    {
        float dir_x, dir_y, dir_z;
        float inner_angle;
        float outer_angle;
        float range;
        float r, g, b;
        float intensity;
    } ke_spot_light_component;

    typedef struct ke_light_render_system ke_light_render_system;

    KE_FRAMEWORK_API void ke_light_render_system_destroy(ke_light_render_system *system);

    KE_FRAMEWORK_API ke_component_id ke_light_render_system_directional_id(const ke_light_render_system *system);
    KE_FRAMEWORK_API ke_component_id ke_light_render_system_point_id(const ke_light_render_system *system);
    KE_FRAMEWORK_API ke_component_id ke_light_render_system_spot_id(const ke_light_render_system *system);

    KE_FRAMEWORK_API void ke_light_render_system_get_system_params(
        ke_light_render_system *system, ke_system_params *out_params);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_LIGHT_RENDER_SYSTEM_H_
