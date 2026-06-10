#ifndef KERNEL_ENGINE_KERNEL_RUNTIME_SYSTEM_CTX_H_
#define KERNEL_ENGINE_KERNEL_RUNTIME_SYSTEM_CTX_H_

// ke_system_ctx — the universal doorway every system uses to touch component
// memory. Lives only for the duration of one execute() callback; constructed
// by the scheduler from the system's declared access_list and the borrowed
// ke_ecs*. In the R2.5c-final build, debug builds check every access against
// the declared list (§15.8). In this prototype, accesses pass through to the
// ke_ecs vtable without checking.

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/types.h>
#include <kernel_engine/kernel/world/ecs.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_system_ctx ke_system_ctx;

// ── Component access through the funnel ─────────────────────────────────────

/// Returns a writable pointer to entity's component. In debug (R2.5c-final),
/// asserts cid is in the system's declared writes; in this prototype, direct
/// pass-through to ke_ecs.
KE_API void *ke_system_ctx_get_mut(ke_system_ctx *ctx, ke_component_id cid, ke_entity entity);

/// Returns a read-only pointer to entity's component. Same checking story as
/// _get_mut, against the declared reads set.
KE_API const void *ke_system_ctx_get(ke_system_ctx *ctx, ke_component_id cid, ke_entity entity);

/// Single-component query: fills out_entities + out_data + out_count with the
/// matched packed arrays. Multi-component query + With/Without filters arrive
/// in R2.5c-final with the ke_ecs surface expansion.
KE_API void ke_system_ctx_query(ke_system_ctx *ctx, ke_component_id cid,
                                ke_entity **out_entities, void **out_data, size_t *out_count);

// ── Deferred mutations ──────────────────────────────────────────────────────
// Queued and applied at the next wave barrier. STUBS in the prototype — each
// returns KE_ERROR_NOT_INITIALIZED so callers that need them fail loudly;
// R2.5c-final wires the real defer queue.

KE_API ke_result ke_system_ctx_spawn(ke_system_ctx *ctx, ke_entity *out_entity);
KE_API ke_result ke_system_ctx_attach(ke_system_ctx *ctx, ke_entity entity,
                                       ke_component_id cid, const void *data, size_t size);
KE_API ke_result ke_system_ctx_detach(ke_system_ctx *ctx, ke_entity entity, ke_component_id cid);
KE_API ke_result ke_system_ctx_despawn(ke_system_ctx *ctx, ke_entity entity);

#ifdef __cplusplus
}
#endif

#endif  // KERNEL_ENGINE_KERNEL_RUNTIME_SYSTEM_CTX_H_
