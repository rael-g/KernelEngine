#ifndef KERNEL_ENGINE_SCHEDULING_SCHEDULE_H_
#define KERNEL_ENGINE_SCHEDULING_SCHEDULE_H_

#include <kernel_engine/tasks/completion.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/commands.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_schedule     ke_schedule;
typedef struct ke_schedule_ctx ke_schedule_ctx;

typedef uint32_t ke_schedule_set_id;
typedef uint64_t ke_schedule_system_id;

/// [bag] An ordering set: a named anchor that systems join and that is ordered against other sets.
typedef struct ke_schedule_set_desc {
    /// [utf8] Identifies the set in diagnostics.
    const char *name;
    /// [array_of:after_count] Sets whose systems all run before this set's.
    const ke_schedule_set_id *after;
    uint32_t                  after_count;
} ke_schedule_set_desc;

/// One call of a system body, once per run of the schedule, or once per slice when the system is
/// per_entity. A failure is carried to the caller of run, which fails with it; the rest of the wave
/// still runs, and no later wave starts.
/// @param ctx       The body's only doorway to component memory for this call.
/// @param user_data [context] Forwarded from register_system.
/// @param dt        The dt run was given.
/// @return KE_OK, or the code of the work the body could not finish.
typedef ke_result (*ke_schedule_execute_fn)(ke_schedule_ctx *ctx, void *user_data, float dt);

/// Whether a system runs in this run of its schedule; asked once per run, before the first wave,
/// on the thread that called run. A failure fails the run before any wave starts.
/// @param user_data [context] Forwarded from register_system.
/// @param out_runs [out] Receives whether the system runs.
/// @return KE_OK, or the code of the failure that kept it from answering.
typedef ke_result (*ke_schedule_condition_fn)(void *user_data, bool *out_runs);

/// [bag] A system: a body, the sets it joins and what it touches.
typedef struct ke_schedule_system_desc {
    /// [utf8] Identifies the system in diagnostics and in the failure its body raises.
    const char *name;
    /// [context] Forwarded unchanged to every call of the body and of the condition.
    void *user_data;
    /// [closure:user_data, retained:return] The body.
    ke_schedule_execute_fn execute;
    /// [optional, closure:user_data, retained:return] When set, the system runs only in the runs
    /// it answers true for.
    ke_schedule_condition_fn condition;
    /// [array_of:query_count] Queries the body reads through ke_schedule_ctx.view, in this order.
    const ke_ecs_query_desc *queries;
    uint32_t                 query_count;
    /// [array_of:access_count] Components the system touches that no query term covers.
    const ke_ecs_query_term *access;
    uint32_t                 access_count;
    /// [array_of:set_count] The sets the system joins, at least one.
    const ke_schedule_set_id *sets;
    uint32_t                  set_count;
    /// The body's work on one entity is independent of every other; the schedule may run it as
    /// several concurrent slices of the same entity set.
    bool per_entity;
    /// The body runs alone at the start of the run, and what it records is applied before the
    /// other systems run. Its access does not order it.
    bool exclusive;
} ke_schedule_system_desc;

/// [interface] Orders the systems of one world by what they touch and the sets they join, and runs
/// them on the job system. The systems of a set run after those of the sets it follows, and a
/// writer of a component before its readers. Two systems conflict when they touch the same
/// component, at least one writes it, and their queries can match the same entity; queries one of
/// which excludes a component the other requires never do. Two writers with no other order run in
/// an order this contract leaves open, and are reported as ambiguous in the log; the run order is
/// neither promised nor forbidden to repeat.
typedef struct ke_schedule {
    void *handle;

    /// Registers an ordering set.
    /// @param out_id [out] Receives the set's id.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a missing name or an unknown set in `after`;
    ///         KE_RESULT_NOT_SUPPORTED from a body; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*register_set)(ke_schedule *self, const ke_schedule_set_desc *desc, ke_schedule_set_id *out_id);
    /// Registers a system. From a body, it takes effect with the next run.
    /// @param out_id [out] Receives the system's id.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a missing name or body, no set, an unknown set,
    ///         a query with no terms, or a term with no access or an unknown one;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*register_system)(ke_schedule *self, const ke_schedule_system_desc *desc, ke_schedule_system_id *out_id);
    /// Removes a system. From a body, it takes effect with the next run.
    /// @return KE_OK, or KE_RESULT_NOT_FOUND when no system has that id.
    ke_result (*unregister_system)(ke_schedule *self, ke_schedule_system_id id);
    /// Applies what bodies registered and removed and what the caller recorded into commands, then
    /// starts a run of the systems. A system's condition is asked once per run, after everything
    /// ordered before the system finished; a failing condition fails the run. An exclusive system
    /// runs with no other system of the schedule. What a body records is applied before any system
    /// ordered after it starts, and at the latest when the run ends. The run ends with the first
    /// failure, and a system not yet started then may or may not run.
    /// @param out_completion [out] Receives the run's completion, which carries the first failure
    ///        of a condition, a body or its commands, and which the caller releases.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a negative @p dt or a null @p out_completion;
    ///         KE_RESULT_NOT_SUPPORTED from a body or while a run is in flight; KE_RESULT_GENERAL
    ///         when the order has a cycle, or an ambiguity the schedule was created to refuse, the
    ///         systems involved named in the log; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*run)(ke_schedule *self, float dt, ke_completion **out_completion);

    /// The queue the caller records structural changes into between runs; the next run applies it
    /// first. Only the thread that calls run records into it.
    /// @return [borrowed] The queue, owned by the schedule.
    ke_ecs_commands *(*commands)(ke_schedule *self);

    /// Whether a registered system reads @p component, through a query term or its access; a system
    /// registered from a body counts from the next run. Callable from a body.
    bool (*reads)(ke_schedule *self, ke_component_id component);
} ke_schedule;


/// [owner]
typedef struct ke_schedule_handle {
    ke_schedule *ref;
    void (*destroy)(ke_schedule *self);
} ke_schedule_handle;

/// [bag] One set of a schedule, as a module joins its systems to it: the schedule and the set's id there.
typedef struct ke_schedule_set {
    /// [borrowed] The schedule the set is registered in.
    ke_schedule *schedule;
    ke_schedule_set_id id;
} ke_schedule_set;

/// What one call of a system body is given: the entities its queries resolved to, its share of
/// them, and the queue it records structural changes into. It means nothing outside the call.
struct ke_schedule_ctx {
    void *handle;

    /// The queue the body records structural changes into, applied before any system ordered after
    /// it starts.
    ke_ecs_commands *commands;

    /// The resolved segments of the query at @p query_index, valid for the call.
    /// @param out_count [out]
    /// @return [array_of:out_count] The segments; NULL for an index past the system's queries.
    const ke_ecs_segment *(*view)(ke_schedule_ctx *self, uint32_t query_index, size_t *out_count);

    /// Which share of its entity set this call owns: *out_index in [0, *out_count). A system
    /// that is not per_entity always gets index 0 of count 1.
    /// @param out_index [out]
    /// @param out_count [out]
    void (*slice)(ke_schedule_ctx *self, uint32_t *out_index, uint32_t *out_count);
};

#ifdef __cplusplus
}
#endif

#endif
