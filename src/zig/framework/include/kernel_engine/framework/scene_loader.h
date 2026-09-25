#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/variant.h>
struct ke_world;

#ifdef __cplusplus
extern "C"
{
#endif

    /** Builds and binds the script an entity's declared type names.
     * @param ctx       [context] Opaque context forwarded from register_script_factory.
     * @param entity    The entity the script is bound to.
     * @param type_name [utf8] Qualified node type name, as the scene file spells it.
     * @param out_error Set when the factory rejects the entity; the load fails with it.
     * @return false when no script could be built for @p type_name. */
    typedef bool (*ke_script_factory_func)(void *ctx, ke_entity entity,
                                           const char *type_name, ke_error **out_error);


    typedef struct ke_scene_loader
    {
        void *handle;

        /** Loads the scene at @p path, instantiating every entity it declares.
         * @param path [utf8] Path to the scene file. */
        bool (*load)(struct ke_scene_loader *self, const char *path, ke_error **out_error);

        /** Registers the factory consulted for every entity that declares a type.
         * Replaces any factory registered before it.
         * @param factory [closure:ctx,retained] Consulted once per typed entity.
         * @param ctx     Forwarded to @p factory unchanged. */
        bool (*register_script_factory)(struct ke_scene_loader *self,
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

#endif
