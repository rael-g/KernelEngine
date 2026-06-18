#ifndef KERNEL_ENGINE_ECS_KE_ECS_H_
#define KERNEL_ENGINE_ECS_KE_ECS_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/ecs/ecs.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_ecs
    {
        void *handle;

        ke_entity (*entity_create)(struct ke_ecs *self);
        void      (*entity_destroy)(struct ke_ecs *self, ke_entity entity);

        ke_component_id (*component_register)(struct ke_ecs *self,
                                               const char    *name,
                                               size_t         element_size);

        ke_result (*component_lookup)(struct ke_ecs     *self,
                                      const char        *name,
                                      ke_component_meta *out_meta,
                                      ke_error         **out_error);

        void *(*component_add)(struct ke_ecs *self,
                               ke_entity      entity,
                               ke_component_id component);

        void (*component_remove)(struct ke_ecs *self,
                                 ke_entity      entity,
                                 ke_component_id component);

        void *(*component_get)(struct ke_ecs *self,
                               ke_entity      entity,
                               ke_component_id component);

        void (*query)(struct ke_ecs  *self,
                      ke_component_id component,
                      ke_entity     **out_entities,
                      void          **out_data,
                      size_t         *out_count);


    } ke_ecs;

    typedef struct ke_ecs_handle
    {
        ke_ecs *ref;
        void (*destroy)(ke_ecs *self);
    } ke_ecs_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_ECS_KE_ECS_H_
