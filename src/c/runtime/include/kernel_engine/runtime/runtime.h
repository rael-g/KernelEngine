#ifndef KERNEL_ENGINE_RUNTIME_RUNTIME_H_
#define KERNEL_ENGINE_RUNTIME_RUNTIME_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_runtime    ke_runtime;
typedef struct ke_system_ctx ke_system_ctx;

typedef uint64_t ke_module_id;
typedef uint64_t ke_system_id;

typedef enum ke_phase {
    KE_PHASE_STARTUP      = 0,
    KE_PHASE_PRE_UPDATE   = 1,
    KE_PHASE_FIXED_UPDATE = 2,
    KE_PHASE_UPDATE       = 3,
    KE_PHASE_POST_UPDATE  = 4,
    // Render systems run here, after the sim→render snapshot swap. Reads of
    // double-buffered components route to the snapshot side (§16).
    KE_PHASE_RENDER       = 5,
    KE_PHASE_SHUTDOWN     = 6,
} ke_phase;

typedef enum ke_access {
    KE_ACCESS_READ  = 1 << 0,
    KE_ACCESS_WRITE = 1 << 1,
} ke_access;

typedef struct ke_component_access {
    ke_component_id cid;
    ke_access       access;
} ke_component_access;

/// A query a system reads through: a tuple of components (matched together) with
/// the access mode the scheduler uses to order waves. Resolved into archetype
/// segments before the wave; the system body reads them via ke_system_ctx_view.
typedef struct ke_query_decl {
    ke_component_access terms[KE_QUERY_MAX_TERMS];
    uint32_t            term_count;
} ke_query_decl;

typedef struct ke_runtime_module_params {
    const char *name;
    void       *user_data;
    bool (*on_load)(ke_runtime *runtime, void *user_data, ke_error **out_error);
    void      (*on_unload)(ke_runtime *runtime, void *user_data);
} ke_runtime_module_params;

typedef struct ke_runtime_system_params {
    const char *name;
    ke_phase    phase;

    /// Queries the system reads through. The runtime registers them, derives the
    /// scheduling access list from their terms, and resolves them into segments
    /// the body reads via ke_system_ctx_view.
    const ke_query_decl *queries;
    uint32_t             query_count;

    /// Cids the system touches that no query term covers, folded into the derived
    /// set so the wave-builder still orders on them: ordering-only tags (render
    /// resources carry no data) and entity-keyed reads via ke_system_ctx_get.
    const ke_component_access *access_list;
    uint32_t                   access_count;

    uint32_t pinned_thread;

    void *user_data;
    void (*execute)(ke_system_ctx *ctx, void *user_data, float dt);
} ke_runtime_system_params;

typedef struct ke_runtime {
    void *handle;

    ke_module_id (*register_module)(ke_runtime *self, const ke_runtime_module_params *p, ke_error **out_error);
    ke_system_id (*register_system)(ke_runtime *self, const ke_runtime_system_params *p, ke_error **out_error);
    bool         (*tick)(ke_runtime *self, float dt, ke_error **out_error);

    /// Blocks until any render phase dispatched by a previous tick() has
    /// finished. tick() dispatches render asynchronously and returns before it
    /// completes (§16); callers that need to tear down render-owned native
    /// resources (GPU device, swapchain surface) must call this first, or the
    /// still-running render phase races the teardown. A no-op if nothing is
    /// pending.
    void (*flush_render)(ke_runtime *self);
} ke_runtime;

typedef struct ke_runtime_handle {
    ke_runtime *ref;
    void (*destroy)(ke_runtime *self);
} ke_runtime_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RUNTIME_RUNTIME_H_
