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

// A deferred structural operation, run serially at the wave barrier (main
// thread, after the wave's parallel bodies have all returned) where entity
// creation/destruction and archetype moves are legal. `user` points to the
// copied payload the caller passed to defer. `ecs` is the live world.
typedef void (*ke_defer_fn)(ke_ecs *ecs, void *user);

// ABI-stable vtable — the system body's operations on its own context. Callers
// invoke these through the ke_system_ctx they receive (ctx->reserve(ctx), ...),
// so a consumer needs only this header, never a link to ke_runtime. `handle`
// is runtime-private. The free ke_system_ctx_* functions below are thin
// wrappers over these slots, kept for callers loaded at runtime (C#) or already
// linking ke_runtime (Zig render passes).
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

// Reserve a real, usable entity id immediately (routes to ke_ecs->entity_reserve).
// Safe to call inside a system body during a parallel wave. Unlike spawn (whose
// id is only assigned at the wave barrier), the returned id is valid at once and
// can be referenced — used as a parent, stored, or given components via attach
// (applied at the barrier). This is the entry point for structural creation that
// needs the id synchronously (e.g. scene-tree node creation from a system).
KE_RUNTIME_API ke_entity ke_system_ctx_reserve(ke_system_ctx *ctx);

// Enqueue an arbitrary structural mutation to run at the wave barrier. The engine
// copies `user_size` bytes of `user` into an internal arena, so the caller's
// buffer need not outlive this call. This is the generic escape valve a builder
// (e.g. the scene tree) uses to perform read-modify-write structural work — such
// as creating a node and linking it into its parent's child list — that the fixed
// spawn/attach/despawn verbs cannot express, while still honoring the "no
// structural change inside a wave" rule. Returns false on OOM.
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

#endif // KERNEL_ENGINE_RUNTIME_SYSTEM_CTX_H_
