#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_LOADER_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/commands.h>
#include <kernel_engine/ecs/variant.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** Builds and binds the script an entity's declared type names.
     * @param ctx       [context] Opaque context forwarded from register_script_factory.
     * @param entity    The entity the script is bound to.
     * @param type_name [utf8] Qualified node type name, as the scene file spells it.
     * @return KE_OK, or the failure code that fails the load when no script could be built for
     *         @p type_name. */
    typedef ke_result (*ke_script_factory_func)(void *ctx, ke_entity entity,
                                                const char *type_name);


    typedef struct ke_scene_loader
    {
        void *handle;

        /** Loads the scene at @p path, instantiating every entity it declares.
         * A script factory's refusal of an entity fails the load with the factory's code; what
         * failed, and where in the file, is logged.
         * @param path [utf8] Path to the scene file. */
        ke_result (*load)(struct ke_scene_loader *self, const char *path);

        /** Records into @p commands loading the scene at @p path under @p parent, as load does it
         * at the root, when @p commands is applied; the scene's first entity becomes a child of
         * @p parent. A failure of the recorded load is logged and fails the application of
         * @p commands with its code, and removes what that load made.
         * @param path     [utf8] Path to the scene file; a `res://` path is the project root joined with the
         *                 rest, as for an included scene, and any other is read as load reads it.
         * @param parent   The node the scene is attached under; KE_ENTITY_INVALID attaches it at
         *                 the root.
         * @param commands
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p path or @p commands, or a path
         *         longer than the longest path the platform accepts; the queue's code when it
         *         refuses the recording. */
        ke_result (*instantiate)(struct ke_scene_loader *self, const char *path, ke_entity parent,
                                 ke_ecs_commands *commands);

        /** Registers the factory consulted for every entity that declares a type.
         * Replaces any factory registered before it.
         * @param factory [closure:ctx,retained] Consulted once per typed entity.
         * @param ctx     Forwarded to @p factory unchanged.
         * @return KE_OK, or KE_RESULT_INVALID_ARGUMENT for a null @p factory. */
        ke_result (*register_script_factory)(struct ke_scene_loader *self,
                                             ke_script_factory_func factory,
                                             void *ctx);

    } ke_scene_loader;

    /// [owner]
    typedef struct ke_scene_loader_handle
    {
        ke_scene_loader *ref;
        void (*destroy)(ke_scene_loader *self);
    } ke_scene_loader_handle;

#ifdef __cplusplus
}
#endif

#endif
