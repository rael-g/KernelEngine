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

    // Component registration flags. DOUBLE_BUFFERED gives the component a back
    // buffer (X_snap) so sim N+1 writes the live side while render N reads the
    // snapshot side; the scheduler swaps at the sim→render phase boundary.
    typedef enum ke_component_flags
    {
        KE_COMPONENT_NONE            = 0,
        KE_COMPONENT_DOUBLE_BUFFERED = 1 << 0,
    } ke_component_flags;

    // ── Resolved queries ─────────────────────────────────────────────────────
    // A query is a component tuple registered once. It is resolved (single-thread)
    // into archetype segments before a parallel wave; the wave bodies then read
    // those segments as plain memory and make no ke_ecs call, so the storage is
    // only ever touched from one thread at a time and concurrent reads are safe by
    // construction. See docs/RuntimeArchitectureV2.md §15.

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

        // ── Sim/render snapshot (RuntimeArchitectureV2.md §16) ──────────────
        // Like component_register but honors ke_component_flags (DOUBLE_BUFFERED
        // gives the component a back buffer). component_register == v3 with NONE.
        ke_component_id (*component_register_v3)(struct ke_ecs    *self,
                                                  const char       *name,
                                                  size_t            element_size,
                                                  ke_component_flags flags);

        // Retroactively double-buffer an already-registered component (used by
        // the runtime's startup inference over render-phase access lists).
        // Idempotent; no-op if already double-buffered.
        void (*set_double_buffered)(struct ke_ecs *self, ke_component_id cid);

        // Maps a double-buffered component's live cid to its snapshot cid, so a
        // render-phase read lands on the frozen side. Returns cid unchanged when
        // it is not double-buffered.
        ke_component_id (*snapshot_cid)(struct ke_ecs *self, ke_component_id cid);

        // Copies every double-buffered component's live column into its snapshot
        // column. Called by the scheduler at the sim→render phase boundary.
        // Returns false and sets *out_error on failure (e.g. underlying storage fatal).
        bool (*swap_snapshots)(struct ke_ecs *self, ke_error **out_error);

        // Runs body(ctx) with the world made safe for concurrent reads from
        // multiple threads (the scheduler dispatches a wave of parallel systems
        // inside it). No structural changes happen here — the runtime defers
        // writes and applies them serially after this returns. Implementation-
        // agnostic: a natively read-thread-safe backend may just call body(ctx).
        // Kept last so adding it does not shift existing vtable slot offsets.
        void (*concurrent_reads)(struct ke_ecs *self, void (*body)(void *ctx), void *ctx);

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
        // Unlike entity_create + component_add (structural, unsafe while the world
        // is inside concurrent_reads), this only allocates an id and is safe to
        // call from any wave thread during a parallel dispatch. The entity is alive
        // immediately and may be referenced (e.g. as a parent) and have components
        // attached through the runtime defer queue, applied at the wave barrier.
        ke_entity (*entity_reserve)(struct ke_ecs *self);

        // Maps a live entity to the entity its snapshot components are stored on
        // (a separate "shadow" entity per §16 — never the live entity itself, so
        // unrelated structural churn on the live side never relocates a snapshot
        // column a render read has already resolved). Returns the entity
        // unchanged if it owns no double-buffered component yet. A snapshot-cid
        // read (snapshot_cid) MUST be paired with a snapshot-entity read
        // (this function) — using one without the other looks up the wrong slot.
        // Kept last so adding it does not shift existing vtable slot offsets.
        ke_entity (*snapshot_entity)(struct ke_ecs *self, ke_entity live);

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
