#ifndef KERNEL_ENGINE_RENDER_SCENE_RESOLVE_H_
#define KERNEL_ENGINE_RENDER_SCENE_RESOLVE_H_

#include <kernel_engine/ecs/ecs.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [value] The ids the ecs gave the scene's render components, which the passes are created with.
    typedef struct ke_render_scene_component_ids
    {
        ke_component_id mesh;
        ke_component_id camera;
        ke_component_id directional_light;
        ke_component_id point_light;
        ke_component_id spot_light;
        ke_component_id ambient_light;
        ke_component_id skybox;
        ke_component_id sprite2d;
        ke_component_id label;
        ke_component_id world_transform;
    } ke_render_scene_component_ids;

    /** [interface] The scene's render components, in the main world and paired in the render world, and the systems that give a mesh and a sprite
     * the GPU resources they name. */
    typedef struct ke_render_scene_resolve
    {
        void *handle;

        /** The ids the main world gave the scene's components; valid while the resolve lives. */
        const ke_render_scene_component_ids *(*component_ids)(struct ke_render_scene_resolve *self);
        /** The ids the render world gave the same components, which every extraction copies the main
         * world's into; valid while the resolve lives. */
        const ke_render_scene_component_ids *(*render_component_ids)(struct ke_render_scene_resolve *self);
    } ke_render_scene_resolve;

    /// [owner]
    typedef struct ke_render_scene_resolve_handle
    {
        ke_render_scene_resolve *ref;
        void (*destroy)(ke_render_scene_resolve *self);
    } ke_render_scene_resolve_handle;

#ifdef __cplusplus
}
#endif

#endif
