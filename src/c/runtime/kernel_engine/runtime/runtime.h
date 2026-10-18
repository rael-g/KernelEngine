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
    /// Runs once, before the other phases of the first tick.
    KE_PHASE_STARTUP           = 0,
    KE_PHASE_PRE_UPDATE        = 1,
    /// The three fixed phases run in this order once per fixed step, as many steps as the
    /// tick's time covers, with the step's duration as `dt`.
    KE_PHASE_FIXED_PRE_UPDATE  = 2,
    KE_PHASE_FIXED_UPDATE      = 3,
    KE_PHASE_FIXED_POST_UPDATE = 4,
    KE_PHASE_UPDATE            = 5,
    KE_PHASE_POST_UPDATE       = 6,
    /// Runs asynchronously against the next tick's sim phases. Its systems read
    /// extracted query results, never live storage, and may not mutate structure.
    KE_PHASE_RENDER            = 7,
    /// Runs once when the runtime is destroyed, if a tick ever ran. A failure of its
    /// bodies is not reported.
    KE_PHASE_SHUTDOWN          = 8,
} ke_phase;

typedef enum ke_access {
    KE_ACCESS_READ  = 1 << 0,
    KE_ACCESS_WRITE = 1 << 1,
} ke_access;

/// [value] One component a system touches, and how. Two systems conflict when they name
/// the same component and at least one writes it; conflicting systems never run in the
/// same wave. A system that declares nothing conflicts with nothing, and is
/// therefore free to run concurrently with everything.
typedef struct ke_component_access {
    ke_component_id cid;
    ke_access       access;
} ke_component_access;

/// [borrowed] A query a system reads through: a tuple of components matched together, each
/// with its access mode. The terms are read while
/// register_system runs, and the runtime keeps its own copy.
typedef struct ke_query_decl {
    /// [array_of:term_count] The terms the query matches together.
    const ke_component_access *terms;
    uint32_t                   term_count;
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

    /// [closure:user_data, retained:return, teardown, default:none] Releases what the load
    /// acquired. A module that acquired nothing leaves it out.
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
///                  call. Opaque; pass it to the entry points that take one.
/// @param user_data [context] Opaque context forwarded from register_system.
/// @param dt        Seconds since the previous tick, or the fixed timestep in
///                  the three fixed phases.
/// @param out_error Set when the body cannot finish its work; the tick fails with it.
/// @return false when the body failed.
typedef bool (*ke_system_execute_fn)(ke_system_ctx *ctx, void *user_data, float dt, ke_error **out_error);

typedef struct ke_runtime_system_params {
    /// [utf8] Identifies the system in diagnostics and in the failure a body raises.
    const char *name;

    /// Which phase of the tick the body runs in.
    ke_phase phase;

    /// [context] Forwarded unchanged to every call of the body.
    void *user_data;

    /// [closure:user_data, retained:return] The body itself.
    ke_system_execute_fn execute;

    /// [array_of:query_count, default:empty] Queries the system reads through; the body reads
    /// their resolved segments via ke_system_ctx_view.
    const ke_query_decl *queries;
    uint32_t             query_count;

    /// [array_of:access_count, default:empty] Cids the system touches that no query term
    /// covers, such as ordering-only tags and component access made without a query.
    /// Declaring nothing is not "no opinion" -- it says the system conflicts with nobody,
    /// so it may run concurrently with every other system in its phase. Anything touching
    /// component storage declares it here.
    const ke_component_access *access_list;
    uint32_t                   access_count;

    /// [default:0] The worker the body must run on, or 0 to let any wave thread take it.
    uint32_t pinned_thread;

    /// [default:false] The body's work on one entity is independent of every other entity
    /// it visits. The runtime may then run it as several concurrent slices of the
    /// same entity set, each body call handling the share ke_system_ctx_slice
    /// reports. False keeps the body one call over the whole set.
    ///
    /// What breaks the promise is a body reaching an entity other than the one it is
    /// visiting, or touching state shared across the set.
    bool per_entity;

    /// [array_of:after_count, default:empty, utf8] Names of systems of the same phase this one runs
    /// after, whatever they access. A name is resolved when the phase is built, so it may name a
    /// system registered later; a name no system of the phase carries fails the tick.
    const char *const *after;
    uint32_t           after_count;

    /// [array_of:before_count, default:empty, utf8] Names of systems of the same phase this one runs
    /// before, resolved like `after`.
    const char *const *before;
    uint32_t           before_count;

    /// [default:false] The body runs alone at the start of its phase, before every system of the
    /// phase that is not exclusive, and what it records is applied before they run. Two
    /// exclusive systems are ordered like two writers of one component. Neither its access nor
    /// per_entity orders or splits it.
    bool exclusive;
} ke_runtime_system_params;

/// [interface] Owns the simulation world, dispatches systems across the worker pool and
/// drives the frame loop.
typedef struct ke_runtime {
    void *handle;

    /// Loads a module into the runtime, running its load hook before returning.
    /// @param p [expand] What the module is called and the hooks it registers.
    ke_module_id (*register_module)(ke_runtime *self, const ke_runtime_module_params *p, ke_error **out_error);
    /// Registers a system body against the phase and the component access it declares.
    /// Registered from a body, the system takes effect with the next tick and a refusal
    /// is not reported.
    /// @param p [expand] What the system is called, when it runs, and what it touches.
    /// @return 0 when the system was refused.
    ke_system_id (*register_system)(ke_runtime *self, const ke_runtime_system_params *p, ke_error **out_error);
    /// Removes a system registered earlier. Called from a body, the removal takes effect
    /// with the next tick.
    /// @return false when no system has that id.
    bool (*unregister_system)(ke_runtime *self, ke_system_id id, ke_error **out_error);
    /// The id of the system registered last and still registered, or 0 when there is none.
    ke_system_id (*last_system)(ke_runtime *self);

    /// Declares @p member one of the members of the exclusive group @p group: no entity holds
    /// two members of one group. Two systems whose every query requires a different member of
    /// the same group touch disjoint entities, so what they access through their queries puts
    /// no order between them; what their access lists name still does.
    /// @return false when @p group equals @p member or the declaration cannot be stored.
    bool (*declare_exclusive)(ke_runtime *self, ke_component_id group, ke_component_id member, ke_error **out_error);
    /// Declares that whoever owns @p cid orders the systems writing it, so the runtime puts no
    /// order between two writers of @p cid. A writer still runs before a system that only
    /// reads it.
    /// @return false when the declaration cannot be stored.
    bool (*declare_self_ordered)(ke_runtime *self, ke_component_id cid, ke_error **out_error);
    /// Builds the order of every phase as the next tick would. Within a phase, a system runs
    /// after the systems it names in `after` and before those it names in `before`, a writer of a component before a system that only
    /// reads it, and of two writers with neither order, the one registered first runs first: an
    /// ambiguity.
    /// @param refuse_ambiguity When true, an ambiguity fails the check too.
    /// @return false with the error naming the systems when an `after` or a `before` names no
    ///         system of its phase, the order has a cycle, or, when refused, two writers are ambiguous.
    bool (*check_order)(ke_runtime *self, bool refuse_ambiguity, ke_error **out_error);

    /// [drains] Runs one tick: every sim phase in order, then the render phase.
    ///
    /// This is where a body that failed during the tick is answered for.
    /// @return false when a body of this tick failed.
    bool (*tick)(ke_runtime *self, float dt, ke_error **out_error);

    /// [drains, name:Flush] Blocks until any render phase dispatched by a previous tick() has
    /// finished, and fails with whatever a body of that phase failed with. That
    /// phase outlives the tick that dispatched it, so this is where its failure is
    /// reported rather than by the tick that started it.
    ///
    /// tick() dispatches render asynchronously and returns before it completes;
    /// callers that need to tear down render-owned native resources must call this first, or the still-running render phase
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
