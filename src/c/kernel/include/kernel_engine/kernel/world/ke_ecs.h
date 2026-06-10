#ifndef KERNEL_ENGINE_KERNEL_WORLD_KE_ECS_H_
#define KERNEL_ENGINE_KERNEL_WORLD_KE_ECS_H_

// ke_ecs — language-agnostic ECS vtable contract (Tier S — S5 / Tier K K1-K2).
//
// Today the engine ships one implementation: sparse-set (ke_ecs_sparse_set_create).
// A future archetype plugin will provide a second vtable without touching this header.
// Language bindings (Lua, Python, …) reference ke_ecs* directly and are immune to
// which implementation is behind it.
//
// The current sparse-set body lives in src/c/kernel/src/world/ecs.c while the
// round-trip is validated. Once validated, it moves to src/cpp/ecs/sparse_set/ (Tier K K2).

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/world/ecs.h>  // ke_entity, ke_component_id
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_ecs
    {
        void *handle; // opaque; owned by the implementation

        // ── Entity lifetime ───────────────────────────────────────────────────

        ke_entity (*entity_create)(struct ke_ecs *self);
        void      (*entity_destroy)(struct ke_ecs *self, ke_entity entity);

        // ── Component schema ──────────────────────────────────────────────────

        ke_component_id (*component_register)(struct ke_ecs *self,
                                               const char    *name,
                                               size_t         element_size);

        /// Resolves a previously-registered component by name. Writes cid + size +
        /// field metadata into *out_meta on success. Returns KE_ERROR_NOT_FOUND when no
        /// component with that name is known. Bindings use this to discover engine-
        /// defined components (e.g. "scene_properties" written by the SceneLoader) at
        /// runtime without hard-coding the cid.
        ke_result (*component_lookup)(struct ke_ecs *self,
                                      const char    *name,
                                      ke_component_meta *out_meta);

        // ── Component data ────────────────────────────────────────────────────

        /// Adds a zero-initialised component slot to entity; returns a pointer to it.
        void *(*component_add)(struct ke_ecs *self,
                               ke_entity      entity,
                               ke_component_id component);

        void (*component_remove)(struct ke_ecs *self,
                                 ke_entity      entity,
                                 ke_component_id component);

        /// Returns a pointer to the component, or NULL if the entity does not have it.
        void *(*component_get)(struct ke_ecs *self,
                               ke_entity      entity,
                               ke_component_id component);

        // ── Query ─────────────────────────────────────────────────────────────

        /// Zero-copy query: fills *out_entities and *out_data with pointers into the
        /// contiguous storage arrays. Pointers are valid until the next structural change.
        void (*query)(struct ke_ecs  *self,
                      ke_component_id component,
                      ke_entity     **out_entities,
                      void          **out_data,
                      size_t         *out_count);

        // ── Lifecycle ─────────────────────────────────────────────────────────

        /// Releases the ke_ecs wrapper struct. Does NOT destroy the underlying
        /// ke_ecs_registry (the world still owns that lifetime).
        void (*destroy)(struct ke_ecs *self);

    } ke_ecs;

    // ── Factory ───────────────────────────────────────────────────────────────

    /// Creates a ke_ecs vtable backed by an existing ke_ecs_registry.
    /// Ownership: the caller owns the returned ke_ecs*; call ke_ecs->destroy() when done.
    /// The underlying registry is NOT destroyed by ke_ecs->destroy().
    KE_API ke_result ke_ecs_sparse_set_create(ke_ecs_registry *registry,
                                               ke_allocator    *alloc,
                                               ke_ecs         **out_ecs);

    typedef struct ke_ecs_flecs_params
    {
        int reserved;  // empty for the spike; expanded as the surface grows
    } ke_ecs_flecs_params;

    /// Creates a ke_ecs vtable backed by an internally-owned flecs world.
    /// Ownership: the caller owns the returned ke_ecs*; call ke_ecs->destroy() when done.
    /// The underlying flecs world is created at ke_ecs_flecs_create() and destroyed by
    /// ke_ecs->destroy(). The flecs build used by this impl strips FLECS_PIPELINE /
    /// FLECS_SYSTEM / FLECS_TIMER addons — flecs is used as storage + queries + observers
    /// only; the scheduler is the in-house ke_runtime (kernel/runtime/runtime_create.h).
    KE_API ke_result ke_ecs_flecs_create(ke_allocator              *alloc,
                                          const ke_ecs_flecs_params *params,
                                          ke_ecs                   **out_ecs);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_WORLD_KE_ECS_H_
