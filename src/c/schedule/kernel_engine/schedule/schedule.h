#ifndef KERNEL_ENGINE_SCHEDULE_SCHEDULE_H_
#define KERNEL_ENGINE_SCHEDULE_SCHEDULE_H_

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

/// [value] One system, as the built order places it.
typedef struct ke_schedule_system_order {
    ke_schedule_system_id id;
    /// The wave the system runs in; systems of one wave run concurrently.
    uint32_t wave;
    /// The system and one registered before it write a component with nothing else ordering them;
    /// the earlier one runs first.
    bool ambiguous;
} ke_schedule_system_order;

/// [interface] Orders the systems of one world by what they touch and the sets they join, and runs
/// them wave by wave across the task pool. Two systems conflict when they touch the same component,
/// at least one writes it, and their queries can match the same entity: queries one of which
/// excludes a component the other requires, or requiring different members of one exclusive
/// group, never do.
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
    /// Declares @p member one of the members of the exclusive group @p group: no entity holds two
    /// members of one group, so queries requiring different members do not conflict.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT when @p group equals @p member;
    ///         KE_RESULT_NOT_SUPPORTED from a body; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*declare_exclusive)(ke_schedule *self, ke_component_id group, ke_component_id member);

    /// Builds the order if a registration changed since the last build; run builds the same way.
    /// The systems of a set run after those of the sets it follows, a writer of a component before
    /// its readers, and of two writers with no other order, the one registered first: an ambiguity.
    /// @param refuse_ambiguity When true, an ambiguity fails the build.
    /// @return KE_OK; KE_RESULT_GENERAL when the order has a cycle or a refused ambiguity, the
    ///         systems involved named in the log; KE_RESULT_NOT_SUPPORTED from a body;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*build)(ke_schedule *self, bool refuse_ambiguity);
    /// The built order, in registration order.
    /// @param out_systems [out,array_of:capacity] Receives one entry per system.
    /// @param out_count [out] Receives the number of systems.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for too small a capacity; KE_RESULT_NOT_SUPPORTED
    ///         from a body; the code build fails with.
    ke_result (*describe)(ke_schedule *self, ke_schedule_system_order *out_systems, uint32_t capacity,
                          uint32_t *out_count);

    /// Applies what bodies registered and removed, then what the caller recorded into commands,
    /// then runs the systems whose condition holds, wave by wave, applying what each wave recorded
    /// before the next starts.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a negative @p dt; KE_RESULT_NOT_SUPPORTED from
    ///         a body; the code build fails with; the code a condition, a body or its commands
    ///         failed with.
    ke_result (*run)(ke_schedule *self, float dt);

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

/// What one call of a system body is given: the entities its queries resolved to, its share of
/// them, and the queue it records structural changes into. It means nothing outside the call.
struct ke_schedule_ctx {
    void *handle;

    /// The queue the body records structural changes into, applied when its wave ends.
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
