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

KE_RUNTIME_API void       *ke_system_ctx_get_mut(ke_system_ctx *ctx, ke_component_id cid,
                                                    ke_entity entity);
KE_RUNTIME_API const void *ke_system_ctx_get(ke_system_ctx *ctx, ke_component_id cid,
                                               ke_entity entity);

KE_RUNTIME_API uint32_t ke_system_ctx_check_failures(void);
KE_RUNTIME_API void     ke_system_ctx_reset_check_failures(void);
KE_RUNTIME_API uint32_t ke_system_ctx_defer_applied_count(void);
KE_RUNTIME_API void     ke_system_ctx_reset_defer_applied(void);

KE_RUNTIME_API void ke_runtime_debug_compute_waves(const ke_runtime_system_params *systems,
                                                     uint32_t                        system_count,
                                                     uint32_t                       *out_wave_assignments,
                                                     uint32_t                       *out_wave_count);

KE_RUNTIME_API void ke_system_ctx_query(ke_system_ctx *ctx, ke_component_id cid,
                                          ke_entity **out_entities, void **out_data,
                                          size_t *out_count);

/// Returns the resolved archetype segments for the system's query at query_index
/// (the order the queries were declared in ke_runtime_system_params). Sets
/// *out_count to the segment count and returns the segment array; both are valid
/// for the duration of the system body. Makes no ke_ecs call — the segments were
/// resolved single-threaded before the wave. Returns NULL for an out-of-range
/// index or a system that declared no queries.
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

// A deferred structural operation, run serially at the wave barrier (main thread,
// outside concurrent_reads) where entity creation/destruction and archetype moves
// are legal. `user` points to the copied payload the caller passed to
// ke_system_ctx_defer. `ecs` is the live world.
typedef void (*ke_defer_fn)(ke_ecs *ecs, void *user);

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
