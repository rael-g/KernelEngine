#ifndef KERNEL_ENGINE_ECS_KE_ECS_H_
#define KERNEL_ENGINE_ECS_KE_ECS_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/ecs/ecs.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Resolved queries ─────────────────────────────────────────────────────
    // A query is a component tuple registered once. It is resolved (single-thread)
    // into archetype segments before a parallel wave; the wave bodies then read
    // those segments as plain memory and make no ke_ecs call — no method on this
    // contract is ever invoked concurrently from more than one thread, so ke_ecs
    // itself needs no lock, no readonly mode, no thread-safety wrapper of its
    // own. Concurrency is a property of how the runtime calls this contract
    // (resolve serially, then let wave bodies read plain memory), not something
    // ke_ecs provides. See docs/RuntimeArchitectureV2.md §15.

    typedef uint64_t ke_query_id;
#define KE_QUERY_INVALID ((ke_query_id)0)
#define KE_QUERY_MAX_TERMS 8

    // One archetype's slice of a query match: the matched entities, plus one column
    // base pointer per query term (term order = the order passed to query_register;
    // columns[i] is the storage for cids[i], aligned 1:1 with entities). A tag term
    // (zero-size component) has columns[i] == NULL. Pointers stay valid until the
    // next structural change — deferred to the wave barrier — so they are stable
    // for the whole parallel wave.
    typedef struct ke_ecs_segment
    {
        const ke_entity *entities;
        void            *columns[KE_QUERY_MAX_TERMS];
        size_t           count;
    } ke_ecs_segment;

    typedef struct ke_ecs
    {
        void *handle;

        ke_entity (*entity_create)(struct ke_ecs *self);
        void      (*entity_destroy)(struct ke_ecs *self, ke_entity entity);

        ke_component_id (*component_register)(struct ke_ecs *self,
                                               const char    *name,
                                               size_t         element_size);

        bool (*component_lookup)(struct ke_ecs     *self,
                                 const char        *name,
                                 ke_component_meta *out_meta,
                                 ke_error         **out_error);

        void *(*component_add)(struct ke_ecs *self,
                               ke_entity      entity,
                               ke_component_id component);

        void (*component_remove)(struct ke_ecs *self,
                                 ke_entity      entity,
                                 ke_component_id component);

        void *(*component_get)(struct ke_ecs *self,
                               ke_entity      entity,
                               ke_component_id component);

        // Byte size of a registered component's element (0 for a tag or an
        // unrecognized cid). Lets a caller that only holds a cid (no name) size
        // its own copy of a column — e.g. the runtime's render-state extract
        // (RuntimeArchitectureV2.md §16), which copies resolved segment columns
        // into its own buffers and needs to know how many bytes per entity.
        size_t (*component_size)(struct ke_ecs *self, ke_component_id cid);

        // Register a query over a component tuple (entities matching ALL cids).
        // Single-threaded (e.g. at system registration). The backend may cache the
        // match set. Returns KE_QUERY_INVALID on failure. cids[i] maps to a
        // resolved segment's columns[i].
        ke_query_id (*query_register)(struct ke_ecs       *self,
                                       const ke_component_id *cids,
                                       size_t                 cid_count);

        // Resolve a query into archetype segments. MUST be called single-threaded,
        // before a parallel wave. Walks the match once and fills out_segments (up
        // to max_segments); sets *out_count to the segment count produced. After it
        // returns, iterating the segments touches NO backend state — pure memory.
        // This is the only place the backend is touched during a frame's reads.
        void (*query_resolve)(struct ke_ecs   *self,
                              ke_query_id       query,
                              ke_ecs_segment   *out_segments,
                              size_t            max_segments,
                              size_t           *out_count);

        // Reserve a fresh, empty entity id without creating component storage.
        // Unlike entity_create + component_add (structural, single-threaded),
        // this only allocates an id and is safe to call from any wave thread
        // during a parallel dispatch. The entity is alive immediately and may be
        // referenced (e.g. as a parent) and have components attached through the
        // runtime defer queue, applied at the wave barrier.
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

#endif // KERNEL_ENGINE_ECS_KE_ECS_H_
