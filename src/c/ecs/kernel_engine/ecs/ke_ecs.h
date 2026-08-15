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
         * Registering an existing name with a different element_size is an error: the
         * name would otherwise silently alias two unrelated layouts under one cid.
         * @param name [borrowed,utf8] Unique component name.
         * @param element_size Bytes per entity; 0 registers a tag (no storage).
         * @param out_error [out,optional] Set when element_size conflicts with the name's prior registration.
         * @return The component's id, or 0 on error.
         */
        ke_component_id (*component_register)(struct ke_ecs *self,
                                               const char    *name,
                                               size_t         element_size,
                                               ke_error     **out_error);

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
         * Resolves a query into archetype segments. MUST run single-threaded, before
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
         * Reserves an entity id without creating storage. Unlike entity_create this
         * is safe from any wave thread; components attach via the runtime defer queue.
         */
        ke_entity (*entity_reserve)(struct ke_ecs *self);

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
