#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/variant.h>
struct ke_world;

#ifdef __cplusplus
extern "C"
{
#endif

    typedef ke_result (*ke_script_factory_func)(void *ctx, ke_entity entity,
                                                const char *type_name);

    typedef struct ke_scene_properties
    {
        const ke_variant_table_entry *entries;
        uint32_t                      count;
    } ke_scene_properties;

#define KE_SCENE_PROPERTIES_COMPONENT_NAME "scene_properties"

    typedef struct ke_scene_loader
    {
        void *handle;

        ke_result (*load)(struct ke_scene_loader *self, const char *path, ke_error **out_error);

        ke_result (*register_script_factory)(struct ke_scene_loader *self,
                                              ke_script_factory_func factory,
                                              void *ctx, ke_error **out_error);

    } ke_scene_loader;

    typedef struct ke_scene_loader_handle
    {
        ke_scene_loader *ref;
        void (*destroy)(ke_scene_loader *self);
    } ke_scene_loader_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_
