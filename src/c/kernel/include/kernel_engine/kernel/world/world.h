#ifndef KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_
#define KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/world/system.h>
#include <kernel_engine/kernel/engine/frame.h>
#include <kernel_engine/kernel/world/ecs.h>

#ifdef __cplusplus
extern "C" {
#endif

    struct ke_task_scheduler;
    struct ke_frame;

    typedef struct ke_world_params {
        struct ke_allocator *allocator;
    } ke_world_params;

    typedef struct ke_world
    {
        void *handle;
        struct ke_allocator *allocator;
        struct ke_ecs_registry *registry;
        void *internal_data;

        void (*destroy)(struct ke_world *self);
        ke_result (*update)(struct ke_world *self, const struct ke_frame *frame);

        // Registry Access
        struct ke_ecs_registry *(*get_registry)(struct ke_world *self);

        // System Management (Phase 4)
        ke_result (*add_system)(struct ke_world *self, const ke_system_desc *desc);

        // Core Components
        uint32_t (*transform_id)(struct ke_world *self);
        uint32_t (*hierarchy_id)(struct ke_world *self);
        uint32_t (*name_id)(struct ke_world *self);
        uint32_t (*script_id)(struct ke_world *self);

        // Task Scheduler Access
        struct ke_task_scheduler* (*get_task_scheduler)(struct ke_world* self);
    } ke_world;

    KE_API ke_result ke_world_create(const ke_world_params *params, ke_world **out_world);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_WORLD_H_
