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

    struct ke_scheduler;
    struct ke_scene_tree;
    struct ke_logger;
    struct ke_signal_bus;

    /// Fills a component from a scene block's keys.
    ///
    /// Entries are mutable so the callback can mark what it took: a key it
    /// accepted must have `consumed` set, or the loader will report it as one
    /// nothing in the engine wanted.
    ///
    /// @param ctx       [context] Opaque context forwarded from register_component_apply.
    /// @param component The component's memory, already added to the entity.
    /// @param entries   The block's keys, one per key the scene declared.
    /// @param count     Number of entries.
    /// @param out_error Set when the callback rejects a value; the load fails with it.
    /// @return false when a key the callback owns carries a value it cannot map,
    /// which fails the load.
    typedef bool (*ke_component_apply_fn)(void                   *ctx,
                                          void                   *component,
                                          ke_variant_table_entry *entries,
                                          uint32_t                count,
                                          ke_error              **out_error);

    typedef struct ke_world ke_world;

    typedef struct ke_world_params
    {
        struct ke_scheduler *scheduler;
        ke_ecs                   *ecs;
        ke_runtime               *runtime;
        struct ke_scene_tree     *scene_tree;
        const char               *project_root;
        struct ke_logger         *logger;
        /// Signal bus scene-declared connections are wired into; optional,
        /// borrowed. Without one, a scene's connection blocks are reported and
        /// skipped rather than silently doing nothing.
        struct ke_signal_bus     *signal_bus;
    } ke_world_params;

    struct ke_world
    {
        void *handle;

        /** [idiom] The ecs the world was created with. */
        ke_ecs         *(*ecs)(struct ke_world *self);
        /** [idiom] The runtime the world was created with. */
        ke_runtime     *(*runtime)(struct ke_world *self);
        /** [idiom] The scene tree the world was created with. */
        struct ke_scene_tree *(*scene_tree)(struct ke_world *self);

        /** Registers the table describing how a scene block's keys land in this
         * component's memory.
         *
         * Runs before the apply callback registered for the same component, if
         * any: the table covers every field it can describe, the callback is
         * left with what a description cannot express (a unit conversion, an
         * enum spelled as a string). Borrowed; must outlive the world. */
        bool (*register_component_fields)(struct ke_world          *self,
                                          ke_component_id           cid,
                                          const ke_component_field *fields,
                                          uint32_t                  field_count,
                                          ke_error                **out_error);

        /** [idiom] Field table registered for `cid`, or NULL.
         * @param out_count [out]
         * @return [array_of:out_count] */
        const ke_component_field *(*get_component_fields)(struct ke_world *self,
                                                          ke_component_id  cid,
                                                          uint32_t        *out_count);

        /** Registers the callback consulted for what a field table cannot
         * describe. Replaces any callback registered for the same component.
         * @param cid   The component the callback answers for.
         * @param apply [closure:ctx,retained:cid] Consulted after the field table.
         * @param ctx   Forwarded to @p apply unchanged. */
        bool (*register_component_apply)(struct ke_world      *self,
                                         ke_component_id       cid,
                                         ke_component_apply_fn apply,
                                         void                 *ctx,
                                         ke_error            **out_error);

        /** [idiom] Callback registered for `cid`, or NULL, and the context it was
         * registered with.
         * @param out_ctx [out] */
        ke_component_apply_fn (*get_component_apply)(struct ke_world *self,
                                                     ke_component_id  cid,
                                                     void           **out_ctx);

        /** Lets a scene name the component registered as `name` by `alias` as well. The alias
         * answers only while it is unambiguous: a second name registered under the same alias,
         * or a component registered under the alias itself, makes it ambiguous, and a scene must
         * then write the full name. Registering the same pair twice changes nothing.
         * @param alias [borrowed,utf8] The short name.
         * @param name  [borrowed,utf8] The name the component is registered under. */
        bool (*register_component_alias)(struct ke_world *self,
                                         const char      *alias,
                                         const char      *name,
                                         ke_error       **out_error);

        /** Resolves the component name a scene wrote: the component registered under it, else
         * the one its alias stands for. Fails as not found when neither exists, and as an
         * invalid argument naming the candidates when the alias is ambiguous.
         * @param name     [borrowed,utf8] The name the scene wrote.
         * @param out_meta [out] Receives the component's id, size and field metadata. */
        bool (*resolve_component)(struct ke_world   *self,
                                  const char        *name,
                                  ke_component_meta *out_meta,
                                  ke_error         **out_error);

    };

    typedef struct ke_world_handle
    {
        ke_world *ref;
        void (*destroy)(ke_world *self);
    } ke_world_handle;

#ifdef __cplusplus
}
#endif

#endif
