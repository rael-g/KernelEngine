#ifndef KERNEL_ENGINE_ECS_KE_ECS_H_
#define KERNEL_ENGINE_ECS_KE_ECS_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** A component tuple registered once and resolved into archetype segments. */
    typedef uint64_t ke_query_id;
#define KE_QUERY_INVALID ((ke_query_id)0)
#define KE_QUERY_MAX_TERMS 8

    /**
     * One archetype's slice of a query match: the matched entities, plus one
     * column base pointer per query term in the order query_register received
     * them, each aligned 1:1 with `entities`. A tag term's column is NULL.
     * Pointers stay valid until the next structural change.
     */
    typedef struct ke_ecs_segment
    {
        const ke_entity *entities;
        void            *columns[KE_QUERY_MAX_TERMS];
        size_t           count;
    } ke_ecs_segment;

    /** Entity lifetime plus component storage: the engine's ECS contract. */
    typedef struct ke_ecs
    {
        void *handle;

        /** Creates a fresh entity with no components. Structural; single-threaded. */
        ke_entity (*entity_create)(struct ke_ecs *self);

        /** Destroys an entity and all its components. Structural; single-threaded. */
        void      (*entity_destroy)(struct ke_ecs *self, ke_entity entity);

        /**
         * Registers a component type by name, or returns the existing id if already registered.
         *
         * A repeated name must describe the same layout as its first registration.
         * With `fields` the two are compared field by field; without it, only
         * `element_size` is compared, which a same-size field swap or a reordering
         * satisfies.
         *
         * @param name [borrowed,utf8] Unique component name.
         * @param element_size Bytes per entity; 0 registers a tag (no storage).
         * @param fields [borrowed,optional] The type's field layout, normally its
         *        generated field table. Must outlive the ecs. NULL registers the
         *        size alone.
         * @param field_count Entries in `fields`; 0 when `fields` is NULL.
         * @param out_error [out,optional] Set when the layout conflicts with the name's
         *        prior registration, naming the field that disagrees.
         * @return The component's id, or 0 on error.
         */
        ke_component_id (*component_register)(struct ke_ecs            *self,
                                               const char               *name,
                                               size_t                    element_size,
                                               const ke_component_field *fields,
                                               uint32_t                  field_count,
                                               ke_error                **out_error);

        /**
         * [try] Looks up a previously registered component by name.
         * @param name [borrowed,utf8] Component name to find.
         * @param out_meta [out] Receives the component's id, size, and field metadata.
         * @return false if no component of that name is registered.
         */
        bool (*component_lookup)(struct ke_ecs     *self,
                                 const char        *name,
                                 ke_component_meta *out_meta,
                                 ke_error         **out_error);

        /**
         * Attaches a component to an entity, returning its zero-initialized storage.
         * Structural; single-threaded. Returns NULL for an unknown entity or cid.
         */
        void *(*component_add)(struct ke_ecs *self,
                               ke_entity      entity,
                               ke_component_id component);

        /** Detaches a component from an entity. Structural; single-threaded. */
        void (*component_remove)(struct ke_ecs *self,
                                 ke_entity      entity,
                                 ke_component_id component);

        /** Returns an entity's component storage, or NULL if it doesn't have that component. */
        void *(*component_get)(struct ke_ecs *self,
                               ke_entity      entity,
                               ke_component_id component);

        /** Byte size of a registered component's element; 0 for a tag or unknown cid. */
        size_t (*component_size)(struct ke_ecs *self, ke_component_id cid);

        /**
         * Registers a query over a component tuple (entities matching ALL cids).
         * @param cids [borrowed,array_of:cid_count] Component tuple to match.
         * @param cid_count Number of components in the tuple.
         * @return KE_QUERY_INVALID on failure.
         */
        ke_query_id (*query_register)(struct ke_ecs       *self,
                                       const ke_component_id *cids,
                                       size_t                 cid_count);

        /**
         * [raw] Resolves a query into archetype segments. MUST run single-threaded, before
         * a parallel wave; afterwards the segments are plain memory touching no
         * backend state.
         * @param out_segments [out,array_of:max_segments] Receives the matched segments.
         * @param max_segments Capacity of out_segments.
         * @param out_count [out] Receives how many segments were written.
         */
        void (*query_resolve)(struct ke_ecs   *self,
                              ke_query_id       query,
                              ke_ecs_segment   *out_segments,
                              size_t            max_segments,
                              size_t           *out_count);

        /**
         * Reserves an entity id, callable concurrently from any wave thread —
         * the one entity operation that is. The id is usable immediately as a
         * reference; the entity itself appears in the world when component_add
         * first runs for it, which the runtime does at the wave barrier.
         *
         * An implementation may not satisfy this by forwarding to entity_create:
         * the contract is concurrent callability, and a backend whose id
         * allocator walks shared state must keep a separate one for this.
         */
        ke_entity (*entity_reserve)(struct ke_ecs *self);

        /**
         * Brings a reserved id into the world, so an entity that never receives a
         * component still exists. Structural; single-threaded. A no-op for an id
         * that is already alive.
         */
        void (*entity_materialize)(struct ke_ecs *self, ke_entity entity);

    } ke_ecs;

    typedef struct ke_ecs_handle
    {
        ke_ecs *ref;
        void (*destroy)(ke_ecs *self);
    } ke_ecs_handle;

#ifdef __cplusplus
}
#endif

#endif
