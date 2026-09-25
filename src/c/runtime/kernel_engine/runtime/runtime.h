#ifndef KERNEL_ENGINE_RUNTIME_RUNTIME_H_
#define KERNEL_ENGINE_RUNTIME_RUNTIME_H_

#include <kernel_engine/common/error.h>
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
    /// Runs asynchronously against the next tick's sim phases. Its systems read
    /// extracted query results, never live storage, and may not mutate structure.
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

/// Registers the module's components and systems against the runtime it is being
/// loaded into. Runs inside register_module, before that call returns.
/// @param runtime   [self] The runtime the module is being loaded into.
/// @param user_data [context] Opaque context forwarded from register_module.
/// @param out_error Set when the module cannot load; registration fails with it.
/// @return false when the module refused to load.
typedef bool (*ke_module_load_fn)(ke_runtime *runtime, void *user_data, ke_error **out_error);

/// Releases whatever the matching load acquired, as the runtime is torn down.
/// @param runtime   [self] The runtime the module was loaded into.
/// @param user_data [context] Opaque context forwarded from register_module.
typedef void (*ke_module_unload_fn)(ke_runtime *runtime, void *user_data);

typedef struct ke_runtime_module_params {
    /// [utf8] Identifies the module in diagnostics.
    const char *name;

    /// [context] Forwarded unchanged to both hooks.
    void *user_data;

    /// [closure:user_data] Registers the module's components and systems.
    ke_module_load_fn on_load;

    /// [closure:user_data, retained:return, teardown] Releases what the load acquired.
    ke_module_unload_fn on_unload;
} ke_runtime_module_params;

/// One call of a system body. The runtime calls it once per tick the system's
/// phase runs, or once per slice when the system declared per_entity.
///
/// A body runs on a worker thread, so only the type of what it failed with makes
/// the trip back: the runtime carries that type to the thread driving the tick and
/// raises a fresh error there, which tick() then fails with. The remaining bodies
/// of the same wave still run — they were already dispatched — but no later phase
/// of that tick starts.
/// @param ctx       [ctx] The body's only doorway to component memory for this
///                  call. Opaque to a managed caller, which forwards it to the
///                  entry points that take one.
/// @param user_data [context] Opaque context forwarded from register_system.
/// @param dt        Seconds since the previous tick, or the fixed timestep in
///                  KE_PHASE_FIXED_UPDATE.
/// @param out_error Set when the body cannot finish its work; the tick fails with it.
/// @return false when the body failed.
typedef bool (*ke_system_execute_fn)(ke_system_ctx *ctx, void *user_data, float dt, ke_error **out_error);

typedef struct ke_runtime_system_params {
    /// [utf8] Identifies the system in diagnostics and in the failure a body raises.
    const char *name;

    /// Which phase of the tick the body runs in.
    ke_phase phase;

    /// [array_of:query_count] Queries the system reads through. The runtime registers
    /// them, derives the scheduling access list from their terms, and resolves them
    /// into segments the body reads via ke_system_ctx_view.
    const ke_query_decl *queries;
    uint32_t             query_count;

    /// [array_of:access_count] Cids the system touches that no query term covers,
    /// folded into the derived set so the wave-builder still orders on them:
    /// ordering-only tags (render resources carry no data) and entity-keyed reads
    /// via ke_system_ctx_get.
    const ke_component_access *access_list;
    uint32_t                   access_count;

    /// The worker the body must run on, or 0 to let any wave thread take it.
    uint32_t pinned_thread;

    /// The body's work on one entity is independent of every other entity it
    /// visits. The runtime may then run it as several concurrent slices of the
    /// same entity set, each body call handling the share ke_system_ctx_slice
    /// reports. False keeps the body one call over the whole set.
    ///
    /// Two entities are two rows, so per-entity work cannot overlap; what breaks
    /// the promise is a body reaching an entity other than the one it is
    /// visiting, or touching state shared across the set.
    bool per_entity;

    /// [context] Forwarded unchanged to every call of the body.
    void *user_data;

    /// [closure:user_data, retained:return] The body itself.
    ke_system_execute_fn execute;
} ke_runtime_system_params;

typedef struct ke_runtime {
    void *handle;

    /// Loads a module into the runtime, running its load hook before returning.
    /// @param p [expand] What the module is called and the hooks it registers.
    ke_module_id (*register_module)(ke_runtime *self, const ke_runtime_module_params *p, ke_error **out_error);
    /// Registers a system body against the phase and the component access it declares.
    /// @param p [expand] What the system is called, when it runs, and what it touches.
    /// @return 0 when the system was refused.
    ke_system_id (*register_system)(ke_runtime *self, const ke_runtime_system_params *p, ke_error **out_error);

    /// [drains] Runs one tick: every sim phase in order, then the render phase.
    ///
    /// A system body written in a managed language cannot let an exception cross this
    /// boundary, so its binding reports the failure through the body's error lane and
    /// leaves the exception itself with the runtime. This is where a body that failed
    /// during the tick is answered for.
    /// @return false when a body of this tick failed.
    bool (*tick)(ke_runtime *self, float dt, ke_error **out_error);

    /// [drains, name:Flush] Blocks until any render phase dispatched by a previous tick() has
    /// finished, and fails with whatever a body of that phase failed with. That
    /// phase outlives the tick that dispatched it, so this is where its failure is
    /// reported rather than by the tick that started it.
    ///
    /// tick() dispatches render asynchronously and returns before it completes;
    /// callers that need to tear down render-owned native resources (GPU device,
    /// swapchain surface) must call this first, or the still-running render phase
    /// races the teardown. A no-op if nothing is pending.
    /// @return false when a body of the render phase failed.
    bool (*flush_render)(ke_runtime *self, ke_error **out_error);
} ke_runtime;

typedef struct ke_runtime_handle {
    ke_runtime *ref;
    void (*destroy)(ke_runtime *self);
} ke_runtime_handle;

#ifdef __cplusplus
}
#endif

#endif
