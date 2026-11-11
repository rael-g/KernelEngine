#ifndef KERNEL_ENGINE_SCHEDULER_SCHEDULER_H_
#define KERNEL_ENGINE_SCHEDULER_SCHEDULER_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/commands.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_scheduler     ke_scheduler;
typedef struct ke_scheduler_ctx ke_scheduler_ctx;

typedef uint32_t ke_phase_id;
typedef uint32_t ke_set_id;
typedef uint64_t ke_scheduler_system_id;

typedef enum ke_scheduler_access {
    KE_SCHEDULER_ACCESS_READ  = 1 << 0,
    KE_SCHEDULER_ACCESS_WRITE = 1 << 1,
} ke_scheduler_access;

/// How long the value of an id lasts. A system whose every write has a lifetime shorter than
/// persistent, and that no running system reads within that lifetime, is culled.
typedef enum ke_lifetime {
    /// The value outlives every run; writing it is an effect no cull removes.
    KE_LIFETIME_PERSISTENT = 0,
    /// The value lives from the run of the phase it is written in to the end of that run.
    KE_LIFETIME_PHASE      = 1,
    /// The value lives until every phase whose systems read it has run since it was written. Its
    /// writer runs while a system of any phase reads it.
    KE_LIFETIME_UNTIL_READ = 2,
} ke_lifetime;

/// When a phase runs within the ticks of a scheduler.
typedef enum ke_phase_cadence {
    /// Once per tick, with the tick's dt.
    KE_PHASE_CADENCE_EVERY_TICK = 0,
    /// Once per fixed step, as many steps as the tick's time covers, with the fixed dt. Fixed phases
    /// registered one after another run together, in order, at each step.
    KE_PHASE_CADENCE_FIXED      = 1,
    /// Once, before every other phase of the first tick, with a dt of zero.
    KE_PHASE_CADENCE_STARTUP    = 2,
    /// Once, when the scheduler shuts down after a tick ran, with a dt of zero.
    KE_PHASE_CADENCE_SHUTDOWN   = 3,
} ke_phase_cadence;

/// [value] One id a system touches, and how. Two systems conflict when they name the same id
/// and at least one writes it; conflicting systems never run in the same wave.
typedef struct ke_id_access {
    ke_component_id id;
    ke_scheduler_access       access;
} ke_id_access;

/// [borrowed] A query a system reads through: components matched together, each with its access.
typedef struct ke_query_desc {
    /// [array_of:term_count] The terms the query matches together.
    const ke_id_access *terms;
    uint32_t            term_count;
} ke_query_desc;

/// [bag] A phase: a group of systems run together, wave by wave. A tick runs the phases in the order
/// they were registered, each when its cadence says.
typedef struct ke_phase_desc {
    /// [utf8] Identifies the phase in diagnostics.
    const char *name;
    /// When the phase runs.
    ke_phase_cadence cadence;
} ke_phase_desc;

/// [bag] An ordering set: a named anchor of one phase that systems join and that is ordered
/// against other sets of the phase.
typedef struct ke_set_desc {
    /// [utf8] Identifies the set in diagnostics.
    const char *name;
    /// The phase whose systems the set orders.
    ke_phase_id phase;
    /// [array_of:after_count] Sets of the same phase whose systems all run before this set's.
    const ke_set_id *after;
    uint32_t         after_count;
} ke_set_desc;

/// One call of a system body, once per run of its phase, or once per slice when the system is
/// per_entity. A failure is carried to the thread that called tick, which fails with it; the
/// rest of the wave still runs, and no later wave or phase starts.
/// @param ctx       The body's only doorway to component memory for this call.
/// @param user_data [context] Forwarded from register_system.
/// @param dt        The tick's dt, the fixed dt in a fixed phase, zero at startup and shutdown.
/// @return KE_OK, or the code of the work the body could not finish.
typedef ke_result (*ke_scheduler_execute_fn)(ke_scheduler_ctx *ctx, void *user_data, float dt);

/// [bag] A system: a body, the sets it joins and what it touches. It runs in the phase of its sets.
typedef struct ke_system_desc {
    /// [utf8] Identifies the system in diagnostics and in the failure its body raises.
    const char *name;
    /// [context] Forwarded unchanged to every call of the body.
    void *user_data;
    /// [closure:user_data, retained:return] The body.
    ke_scheduler_execute_fn execute;
    /// [array_of:query_count] Queries the body reads through ke_scheduler_ctx.view.
    const ke_query_desc *queries;
    uint32_t             query_count;
    /// [array_of:access_count] Ids the system touches that no query term covers.
    const ke_id_access *access;
    uint32_t            access_count;
    /// [array_of:set_count] The sets the system joins, at least one, all of one phase.
    const ke_set_id *sets;
    uint32_t         set_count;
    /// The body's work on one entity is independent of every other; the scheduler may run it as
    /// several concurrent slices of the same entity set.
    bool per_entity;
    /// The body runs alone at the start of its phase, and what it records is applied before the
    /// other systems of the phase run. Its access does not order it.
    bool exclusive;
} ke_system_desc;

/// [value] One system of a phase, as the built order places it.
typedef struct ke_system_order {
    ke_scheduler_system_id id;
    /// The wave the system runs in; systems of one wave run concurrently.
    uint32_t     wave;
    /// The system does not run: nothing that runs reads what it writes within its lifetime.
    bool         culled;
} ke_system_order;

/// [interface] Orders systems by what they touch and the sets they join, and runs their phases tick by
/// tick across the task pool.
typedef struct ke_scheduler {
    void *handle;

    /// Registers a phase.
    /// @param out_id [out] Receives the phase's id.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a missing name; KE_RESULT_NOT_SUPPORTED from a
    ///         body; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*register_phase)(ke_scheduler *self, const ke_phase_desc *desc, ke_phase_id *out_id);
    /// Registers an ordering set.
    /// @param out_id [out] Receives the set's id.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown phase or a set of `after` from
    ///         another phase; KE_RESULT_NOT_SUPPORTED from a body; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*register_set)(ke_scheduler *self, const ke_set_desc *desc, ke_set_id *out_id);
    /// Registers a system. From a body, it takes effect with the next tick.
    /// @param out_id [out] Receives the system's id.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a missing name or body, no set, an unknown set
    ///         or sets of two phases; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*register_system)(ke_scheduler *self, const ke_system_desc *desc, ke_scheduler_system_id *out_id);
    /// Removes a system. From a body, it takes effect with the next tick.
    /// @return KE_OK, or KE_RESULT_NOT_FOUND when no system has that id.
    ke_result (*unregister_system)(ke_scheduler *self, ke_scheduler_system_id id);
    /// Declares the lifetime of @p id; an id never declared is persistent.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown lifetime; KE_RESULT_NOT_SUPPORTED
    ///         from a body; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*declare_lifetime)(ke_scheduler *self, ke_component_id id, ke_lifetime lifetime);
    /// Declares @p member one of the members of the exclusive group @p group: no entity holds two
    /// members of one group, so queries requiring different members do not conflict.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when @p group equals @p member;
    ///         KE_RESULT_NOT_SUPPORTED from a body; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*declare_exclusive)(ke_scheduler *self, ke_component_id group, ke_component_id member);

    /// Builds the order of every phase whose registrations changed since the last build; tick
    /// builds the same way. Within a phase, the systems of a set run after those of the sets it
    /// follows, a writer of an id before its readers, and of two writers with no other order, the
    /// one registered first: an ambiguity.
    /// @param refuse_ambiguity When true, an ambiguity fails the build.
    /// @return KE_OK; KE_RESULT_GENERAL when an order has a cycle or a refused ambiguity, the
    ///         systems involved named in the log; KE_RESULT_NOT_SUPPORTED from a body;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*build)(ke_scheduler *self, bool refuse_ambiguity);
    /// The built order of @p phase, in registration order.
    /// @param out_systems [out,array_of:capacity] Receives one entry per system of the phase.
    /// @param out_count [out] Receives the number of systems of the phase.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown phase or too small a capacity;
    ///         KE_RESULT_NOT_SUPPORTED from a body; the code build fails with.
    ke_result (*describe_phase)(ke_scheduler *self, ke_phase_id phase, ke_system_order *out_systems,
                                uint32_t capacity, uint32_t *out_count);

    /// Applies what was recorded into commands, then runs the phases in registration order: on the
    /// first tick the startup phases first, then each every-tick phase, and each block of fixed
    /// phases once per fixed step the accumulated time covers, the accumulation capped at
    /// fixed_dt_max_accum.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a negative @p dt; KE_RESULT_NOT_SUPPORTED from a
    ///         body or after shutdown; the code build fails with; the code a body or its commands
    ///         failed with.
    ke_result (*tick)(ke_scheduler *self, float dt);

    /// Runs the shutdown phases once if a tick ran; a later call, and a later tick, do nothing and
    /// are refused respectively. Destroying the scheduler calls it for a caller that did not.
    /// @return KE_OK; KE_RESULT_NOT_SUPPORTED from a body; the code a body failed with.
    ke_result (*shutdown)(ke_scheduler *self);

    /// Records that the program should end; any body or the caller may ask, from any thread.
    void (*request_exit)(ke_scheduler *self);

    /// Whether a request to end the program was recorded.
    bool (*exit_requested)(ke_scheduler *self);

    /// The queue the caller of tick records structural changes into between ticks; the next tick
    /// applies it first. Only the thread that calls tick records into it.
    /// @return [borrowed] The queue, owned by the scheduler.
    ke_ecs_commands *(*commands)(ke_scheduler *self);
} ke_scheduler;

/// [owner]
typedef struct ke_scheduler_handle {
    ke_scheduler *ref;
    void (*destroy)(ke_scheduler *self);
} ke_scheduler_handle;

/// [value] What a scheduler is created with, each field applied as given.
typedef struct ke_scheduler_config {
    /// The dt of a fixed step, in seconds; greater than zero.
    float fixed_dt;
    /// The most time a tick may accumulate for fixed steps, in seconds; the excess is dropped;
    /// greater than zero.
    float fixed_dt_max_accum;
} ke_scheduler_config;

/// What one call of a system body is given: the entities its queries resolved to, its share of
/// them, and the queue it records structural changes into. It means nothing outside the call.
struct ke_scheduler_ctx {
    void *handle;

    /// The queue the body records structural changes into, applied when its wave ends.
    ke_ecs_commands *commands;

    /// The resolved segments of the query at @p query_index, valid for the call.
    /// @param out_count [out]
    /// @return [array_of:out_count] The segments; NULL for an index past the system's queries.
    const ke_ecs_segment *(*view)(ke_scheduler_ctx *self, uint32_t query_index, size_t *out_count);

    /// Which share of its entity set this call owns: *out_index in [0, *out_count). A system
    /// that is not per_entity always gets index 0 of count 1.
    /// @param out_index [out]
    /// @param out_count [out]
    void (*slice)(ke_scheduler_ctx *self, uint32_t *out_index, uint32_t *out_count);
};

#ifdef __cplusplus
}
#endif

#endif
