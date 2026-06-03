#ifndef KERNEL_ENGINE_FRAMEWORK_NODE_TYPE_REGISTRY_H_
#define KERNEL_ENGINE_FRAMEWORK_NODE_TYPE_REGISTRY_H_

#include <kernel_engine/framework/framework_export.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/world/components.h>
#include <kernel_engine/kernel/world/variant.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Node type callbacks ──────────────────────────────────────────────────
    //
    // Each language binding registers one ke_node_type per scriptable node
    // class. The SceneLoader (S3) resolves types by string name, creates
    // entities, then calls create + set_property for each TOML node.
    //
    // The entity is always created BEFORE create() is called — the binding
    // associates its managed object with the entity however it sees fit
    // (e.g. a GCHandle table in C#, a Lua userdata registry in Lua).

    struct ke_node_type_registry;

    /// Called once per node, after the ECS entity already exists.
    /// The binding creates its managed node object and registers it against
    /// the entity. Return KE_OK on success.
    typedef ke_result (*ke_node_create_func)(
        void *ctx, ke_entity entity, const char *name);

    /// Called once per property key/value pair read from the scene file.
    /// The variant is passed by pointer (blittable across the ABI to managed
    /// CLR callbacks); the pointed-to data is valid only for the duration of
    /// this call. The string pointer in a KE_VARIANT_STRING value is likewise
    /// transient — copy if you need to retain it.
    typedef ke_result (*ke_node_set_property_func)(
        void *ctx, ke_entity entity, const char *key, const ke_variant *value);

    // ── Node type descriptor ─────────────────────────────────────────────────

    typedef struct ke_node_type
    {
        const char               *name;         // string key used by the SceneLoader
        void                     *ctx;          // opaque context forwarded to all callbacks
        ke_node_create_func       create;       // required; must not be NULL
        ke_node_set_property_func set_property; // optional; NULL = no-op
    } ke_node_type;

    /// Called by lookup() when a type name is unknown. The handler is expected
    /// to register the type via register_type() so the subsequent retry succeeds.
    /// Returns KE_OK if the type was successfully registered, anything else
    /// causes lookup() to surface KE_ERROR_NOT_FOUND.
    typedef ke_result (*ke_node_type_lookup_miss_func)(
        void *ctx, struct ke_node_type_registry *registry, const char *name);

    // ── Registry vtable ──────────────────────────────────────────────────────

    typedef struct ke_node_type_registry
    {
        void *handle;

        /// Copies the descriptor and stores it under type->name.
        /// Returns KE_ERROR_INVALID_ARGUMENT if type or type->name is NULL,
        /// or if type->create is NULL. Returns KE_ERROR_OUT_OF_MEMORY if
        /// the internal table needs to grow and allocation fails.
        ke_result (*register_type)(struct ke_node_type_registry *self,
                                   const ke_node_type           *type);

        /// Resolves a type by name. On miss, fires the registered lookup_miss
        /// callback (if any) for on-the-fly registration, then retries once.
        /// Returns KE_ERROR_NOT_FOUND if still unknown.
        ke_result (*lookup)(struct ke_node_type_registry *self,
                            const char                   *name,
                            const ke_node_type          **out_type);

        /// Installs a fallback called by lookup() on a miss. Callers (typically
        /// language bindings) use this to defer registration until first use,
        /// avoiding eager scanning of every Node subclass at startup.
        void (*set_lookup_miss)(struct ke_node_type_registry *self,
                                ke_node_type_lookup_miss_func fn,
                                void                         *ctx);

        void (*destroy)(struct ke_node_type_registry *self);
    } ke_node_type_registry;

    // ── Factory ──────────────────────────────────────────────────────────────

    KE_FRAMEWORK_API ke_result ke_node_type_registry_create(
        ke_allocator           *alloc,
        ke_node_type_registry **out_registry);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_NODE_TYPE_REGISTRY_H_
