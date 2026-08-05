#ifndef KERNEL_ENGINE_FRAMEWORK_NODE_HOST_H_
#define KERNEL_ENGINE_FRAMEWORK_NODE_HOST_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/variant.h>
#include <kernel_engine/ecs/component_field.h>
#include <kernel_engine/runtime/runtime.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint32_t ke_node_hook_id;
#define KE_NODE_HOOK_INVALID ((ke_node_hook_id)0)

    /**
     * v0 carries only the proven case (per-tick update, mapped to
     * KE_PHASE_UPDATE). OnBind/OnReady/OnUnbind are additive, not designed yet —
     * see ScriptingArchitectureV2.md §7.
     */
    typedef enum ke_node_hook_kind
    {
        KE_NODE_HOOK_UPDATE = 0,
    } ke_node_hook_kind;

    /**
     * One native->managed dispatch per resolved archetype segment, not per
     * entity — a managed language pays one transition per segment (potentially
     * hundreds of entities), not per entity. columns[i] order = the order
     * access() was called for the hook this callback is bound to.
     */
    typedef void (*ke_node_hook_fn)(void *ctx, const ke_entity *entities,
                                     void *const *columns, size_t count, float dt);

    /**
     * Declares one node type: its own backing component's fields, plus one
     * runtime-dispatched hook per lifecycle callback the type needs. Obtained via
     * ke_node_host.begin_type; consumed and destroyed by ke_node_host.commit,
     * which is the only place any of this is actually registered.
     */
    typedef struct ke_node_type_builder
    {
        void *handle;

        /**
         * Declares a field on the type's own backing component. Declaration order is
         * layout order. KE_VARIANT_STRING/KE_VARIANT_TABLE are not blittable into
         * component memory and fail at commit(), not here — field() itself cannot fail.
         * @param name [utf8]
         */
        bool (*field)(struct ke_node_type_builder *self, const char *name, ke_variant_type type);

        /**
         * Declares a lifecycle hook and the callback it dispatches to.
         * @return KE_NODE_HOOK_INVALID if self is invalid.
         */
        ke_node_hook_id (*hook)(struct ke_node_type_builder *self, ke_node_hook_kind kind,
                                 ke_node_hook_fn fn, void *ctx);

        /**
         * Declares a component `hook` reads/writes, resolved at commit(). component_name
         * either equals the type's own name (self-reference, resolved to the
         * just-registered own component) or must already be registered on the ke_ecs
         * this host was created with.
         * @param component_name [utf8]
         */
        bool (*access)(struct ke_node_type_builder *self, ke_node_hook_id hook,
                       const char *component_name, ke_access access);

    } ke_node_type_builder;

    /**
     * The node-registration middle-end: one native implementation of "a
     * declared type's fields become an ECS component, its hooks become
     * ke_runtime systems", shared by every language binding. See
     * ScriptingArchitectureV2.md for the full design and rationale.
     */
    typedef struct ke_node_host
    {
        void *handle;

        /**
         * Begins declaring a new node type. Fails if type_name is already committed
         * on this host — no hot-reload semantics in v0.
         * @param type_name [utf8]
         */
        ke_node_type_builder *(*begin_type)(struct ke_node_host *self, const char *type_name,
                                            ke_error **out_error);

        /**
         * Verifies every field/hook/access declared on builder, then registers the
         * type's own component and one ke_runtime system per hook, atomically: on
         * any verification failure nothing is registered. Destroys builder either way.
         */
        bool (*commit)(struct ke_node_host *self, ke_node_type_builder *builder, ke_error **out_error);

        /**
         * Creates an entity carrying the registered type's own component,
         * zero-initialized. The caller sets field values after spawn.
         * @param type_name [utf8]
         */
        ke_entity (*spawn)(struct ke_node_host *self, const char *type_name, ke_error **out_error);

        /**
         * Attaches the registered type's own component onto an entity that already
         * exists (e.g. one ke_scene_loader created from a scene file), zero-initialized.
         * @param type_name [utf8]
         */
        bool (*attach)(struct ke_node_host *self, ke_entity entity, const char *type_name,
                       ke_error **out_error);

        /**
         * Introspection as an output: describes a registered type's own fields (name +
         * ke_variant_type) as a variant table, keyed "<field>.type". For tooling and
         * diagnostics — never consumed by this host to decide semantics.
         * @param type_name [utf8]
         */
        bool (*describe)(struct ke_node_host *self, const char *type_name,
                         const ke_variant_table **out, ke_error **out_error);

    } ke_node_host;

    typedef struct ke_node_host_handle
    {
        ke_node_host *ref;
        void (*destroy)(ke_node_host *self);
    } ke_node_host_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_NODE_HOST_H_
