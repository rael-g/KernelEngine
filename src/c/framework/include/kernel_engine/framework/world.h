#ifndef KERNEL_ENGINE_FRAMEWORK_WORLD_H_
#define KERNEL_ENGINE_FRAMEWORK_WORLD_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/variant.h>
#include <kernel_engine/runtime/runtime.h>

#ifdef __cplusplus
extern "C"
{
#endif

    struct ke_task_scheduler;
    struct ke_scene_tree;
    struct ke_logger;

    typedef void (*ke_component_apply_fn)(void                         *component,
                                           const ke_variant_table_entry *entries,
                                           uint32_t                      count);

    typedef struct ke_world ke_world;

    typedef struct ke_world_params
    {
        struct ke_task_scheduler *task_scheduler;
        ke_ecs                   *ecs;
        ke_runtime               *runtime;
        struct ke_scene_tree     *scene_tree;
        const char               *project_root;
        struct ke_logger         *logger;
    } ke_world_params;

    struct ke_world
    {
        void *handle;

        ke_ecs         *(*ecs)(struct ke_world *self);
        ke_runtime     *(*runtime)(struct ke_world *self);
        struct ke_scene_tree *(*scene_tree)(struct ke_world *self);

        ke_result (*register_component_apply)(struct ke_world      *self,
                                               ke_component_id       cid,
                                               ke_component_apply_fn apply,
                                               ke_error            **out_error);

        ke_component_apply_fn (*get_component_apply)(struct ke_world *self,
                                                      ke_component_id  cid);

    };

    typedef struct ke_world_handle
    {
        ke_world *ref;
        void (*destroy)(ke_world *self);
    } ke_world_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_WORLD_H_
