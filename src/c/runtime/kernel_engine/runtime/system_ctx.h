#ifndef KERNEL_ENGINE_RUNTIME_SYSTEM_CTX_H_
#define KERNEL_ENGINE_RUNTIME_SYSTEM_CTX_H_

#include <kernel_engine/common/export.h>
#include <kernel_engine/common/error.h>
#include <kernel_engine/runtime/runtime.h>
#include <kernel_engine/ecs/ecs.h>
#include <stddef.h>

#ifdef KE_RUNTIME_STATIC
#  define KE_RUNTIME_API
#elif defined(KE_RUNTIME_EXPORT)
#  define KE_RUNTIME_API KE_EXPORT
#else
#  define KE_RUNTIME_API KE_IMPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_system_ctx ke_system_ctx;

/// A structural operation run serially at the wave barrier. `user` points at the
/// copy of the payload passed to defer; `ecs` is the live world.
typedef void (*ke_defer_fn)(ke_ecs *ecs, void *user);

/// The operations a system body may perform on its own context, invoked through
/// the ke_system_ctx it receives. `handle` is runtime-private. The free
/// ke_system_ctx_* functions below wrap these slots.
struct ke_system_ctx {
    void *handle;

    const ke_ecs_segment *(*view)(ke_system_ctx *self, uint32_t query_index, size_t *out_count);
    ke_entity (*reserve)(ke_system_ctx *self);
    bool (*defer)(ke_system_ctx *self, ke_defer_fn fn, const void *user, size_t user_size);
    ke_entity (*spawn)(ke_system_ctx *self);
    bool (*attach)(ke_system_ctx *self, ke_entity entity, ke_component_id cid, const void *data, size_t size);
    bool (*detach)(ke_system_ctx *self, ke_entity entity, ke_component_id cid);
    bool (*despawn)(ke_system_ctx *self, ke_entity entity);
};

KE_RUNTIME_API uint32_t ke_system_ctx_defer_applied_count(void);
KE_RUNTIME_API void     ke_system_ctx_reset_defer_applied(void);

KE_RUNTIME_API void ke_runtime_debug_compute_waves(const ke_runtime_system_params *systems,
                                                     uint32_t                        system_count,
                                                     uint32_t                       *out_wave_assignments,
                                                     uint32_t                       *out_wave_count);

/// The system body's only path to component memory. Returns the resolved
/// archetype segments for the system's query at query_index (the order the
/// queries were declared in ke_runtime_system_params). Sets *out_count to the
/// segment count and returns the segment array; both are valid for the duration
/// of the system body. Makes no ke_ecs call — the segments were resolved
/// single-threaded before the wave, because an ECS iterator allocates from
/// storage shared across the wave's parallel systems. Returns NULL for an
/// out-of-range index or a system that declared no queries.
KE_RUNTIME_API const ke_ecs_segment *ke_system_ctx_view(ke_system_ctx *ctx,
                                                          uint32_t query_index,
                                                          size_t *out_count);

/// Reserves an entity id usable immediately, callable during a parallel wave.
/// The id may be referenced at once; components given via attach land at the
/// wave barrier.
KE_RUNTIME_API ke_entity ke_system_ctx_reserve(ke_system_ctx *ctx);

/// Enqueues a structural mutation to run at the wave barrier, for work the fixed
/// spawn/attach/despawn verbs cannot express. `user_size` bytes of `user` are
/// copied, so the caller's buffer need not outlive the call. False on OOM.
KE_RUNTIME_API bool ke_system_ctx_defer(ke_system_ctx *ctx, ke_defer_fn fn,
                                          const void *user, size_t user_size);

KE_RUNTIME_API ke_entity ke_system_ctx_spawn(ke_system_ctx *ctx);
KE_RUNTIME_API bool     ke_system_ctx_attach(ke_system_ctx *ctx, ke_entity entity,
                                               ke_component_id cid, const void *data, size_t size);
KE_RUNTIME_API bool     ke_system_ctx_detach(ke_system_ctx *ctx, ke_entity entity,
                                               ke_component_id cid);
KE_RUNTIME_API bool     ke_system_ctx_despawn(ke_system_ctx *ctx, ke_entity entity);

#ifdef __cplusplus
}
#endif

#endif
