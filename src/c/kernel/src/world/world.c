#include <kernel_engine/kernel/world/world.h>
#include <kernel_engine/kernel/world/ecs.h>
#include <kernel_engine/kernel/context/allocator.h>

typedef struct ke_world_impl
{
    struct ke_scene *scene;
    struct ke_ecs_registry *registry;
    struct ke_render *renderer;
    struct ke_window *window;
    struct ke_allocator *allocator;
    ke_world api;
} ke_world_impl;

static struct ke_scene *world_get_scene(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->scene;
}

static struct ke_ecs_registry *world_get_registry(ke_world *self)
{
    return ((ke_world_impl *)self->handle)->registry;
}

static ke_result world_update(ke_world *self, const struct ke_frame *frame)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    
    // 1. Process Logic (Update scripts/behaviors on nodes)
    // For now we assume nodes call on_update in C.
    // ...

    // 2. Update Scene (Hierarchy)
    impl->scene->update(impl->scene);

    // 3. Process ECS
    // ...

    return KE_OK;
}

static void world_destroy(ke_world *self)
{
    ke_world_impl *impl = (ke_world_impl *)self->handle;
    impl->scene->destroy(impl->scene);
    ke_ecs_registry_destroy(impl->registry);
    impl->allocator->free(impl->allocator, impl);
}

ke_result ke_world_create(const ke_world_descriptor *desc, ke_world **out_world)
{
    if (!desc || !desc->allocator || !out_world) return KE_ERROR_INVALID_ARGUMENT;

    ke_world_impl *impl = (ke_world_impl *)desc->allocator->alloc(desc->allocator, sizeof(ke_world_impl), 0);
    if (!impl) return KE_ERROR_OUT_OF_MEMORY;

    impl->allocator = desc->allocator;
    impl->renderer = desc->renderer;
    impl->window = desc->window;

    ke_scene_descriptor scene_desc = { .allocator = impl->allocator };
    ke_result res = ke_scene_create(&scene_desc, &impl->scene);
    if (res != KE_OK)
    {
        desc->allocator->free(desc->allocator, impl);
        return res;
    }

    res = ke_ecs_registry_create(impl->allocator, &impl->registry);
    if (res != KE_OK)
    {
        impl->scene->destroy(impl->scene);
        desc->allocator->free(desc->allocator, impl);
        return res;
    }

    impl->api.handle = impl;
    impl->api.destroy = world_destroy;
    impl->api.get_scene = world_get_scene;
    impl->api.get_registry = world_get_registry;
    impl->api.update = world_update;

    *out_world = &impl->api;
    return KE_OK;
}
