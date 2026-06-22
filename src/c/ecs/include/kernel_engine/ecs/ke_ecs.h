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

        void (*query)(struct ke_ecs  *self,
                      ke_component_id component,
                      ke_entity     **out_entities,
                      void          **out_data,
                      size_t         *out_count);

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
        void (*swap_snapshots)(struct ke_ecs *self);

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
