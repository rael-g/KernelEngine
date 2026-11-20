#ifndef KERNEL_ENGINE_PART_PART_H_
#define KERNEL_ENGINE_PART_PART_H_

#include <kernel_engine/completion/completion.h>
#include <kernel_engine/logger/log_callback.h>
#include <kernel_engine/result/result.h>
#include <kernel_engine/schedule/schedule.h>
#include <kernel_engine/settings/settings.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// How many instances a slot takes.
typedef enum ke_part_cardinality {
    /// Exactly one.
    KE_PART_CARDINALITY_ONE = 1,
    /// None or one.
    KE_PART_CARDINALITY_OPTIONAL = 2,
    /// Any number.
    KE_PART_CARDINALITY_MANY = 3,
} ke_part_cardinality;

/// [bag] An instance a part needs to be created: what it is called in the part and the contract it must provide.
/// A contract is named by the C type of its vtable, as "ke_ecs".
typedef struct ke_part_slot {
    /// [utf8] Unique among the part's slots.
    const char *name;
    /// [utf8] The contract the bound instances provide.
    const char *contract;
    ke_part_cardinality cardinality;
} ke_part_slot;

/// [bag] A place in the frame where a part runs work: a set of a schedule.
typedef struct ke_part_hook {
    /// [utf8] Unique among the part's hooks.
    const char *name;
    /// [utf8] The set the hook joins when the composition names no set, in the schedule the composition names or,
    /// when it names none, the only schedule that has a set of that name.
    const char *default_set;
} ke_part_hook;

/// [bag] A set a part introduces in the schedule one of its hooks is bound to.
typedef struct ke_part_set {
    /// [utf8] The set's name in that schedule.
    const char *name;
    /// [utf8] The hook whose schedule the set is introduced in.
    const char *hook;
    /// [utf8,optional] A set of that schedule this one runs after; NULL for none.
    const char *after;
} ke_part_set;

/// [bag] The instances bound to one slot. Two of them the composition ordered come in that order; any others in
/// no guaranteed order.
typedef struct ke_part_bound {
    /// [borrowed] Each the instance of the slot's contract; NULL when @p count is zero.
    void *const *instances;
    /// [borrowed] The position of each of @p instances among every instance bound to any slot of the part, counted
    /// from zero: two the composition ordered, within a slot or across slots, have positions in that order. NULL
    /// when @p count is zero.
    const size_t *positions;
    size_t count;
} ke_part_bound;

/// [bag] Where one hook was bound.
typedef struct ke_part_hooked {
    /// [borrowed] Outlives the instance.
    ke_schedule *schedule;
    ke_schedule_set_id set;
} ke_part_hooked;

/// [owner] What has no contract of its own to be released through: an instance a part created, or the systems a
/// module registered. @p destroy takes @p ref.
typedef struct ke_owner {
    void *ref;
    void (*destroy)(void *ref);
} ke_owner;

/// [interface] The description of an implementation: what it provides, what it needs and where it runs, and how it
/// is created from that. A part states facts about its implementation, never a choice of the host.
typedef struct ke_part {
    /// [utf8] The implementation's name, unique among the parts given to one assembly.
    const char *name;
    /// [borrowed] @p provides_count contracts the instance provides, each named by the C type of its vtable; none for
    /// one that provides nothing, as a module.
    const char *const *provides;
    size_t provides_count;
    /// [borrowed] @p slot_count slots, in the order @p create receives them.
    const ke_part_slot *slots;
    size_t slot_count;
    /// [borrowed] @p hook_count hooks, in the order @p create receives them.
    const ke_part_hook *hooks;
    size_t hook_count;
    /// [borrowed] @p set_count sets the part introduces.
    const ke_part_set *sets;
    size_t set_count;

    /// Creates an instance.
    /// @param slots [borrowed] One per slot, in the part's order; valid during the call, the instances for the
    ///        instance's lifetime.
    /// @param hooks [borrowed] One per hook, in the part's order.
    /// @param settings [borrowed] The instance's section; read during the call.
    /// @param out_instance [out] Receives the owner of the instance; left zeroed on failure.
    /// @return KE_OK, or the code the implementation's factory failed with.
    ke_result (*create)(const struct ke_part *self, const ke_part_bound *slots, const ke_part_hooked *hooks,
                        ke_settings *settings, ke_owner *out_instance);

    /// [optional] Gives the instance of the contract at @p index of @p provides; NULL for a part that provides one
    /// contract, whose instance is the owner's ref.
    /// @param instance The owner's ref.
    /// @param index Below @p provides_count.
    void *(*provided)(void *instance, size_t index);

    /// [optional] Gives the completion an instance finishes becoming usable with; NULL for an implementation that
    /// is usable once created.
    /// @param instance The owner's ref.
    /// @param out_completion [out] Receives the completion, released by the caller; NULL when already usable.
    ke_result (*ready)(void *instance, ke_completion **out_completion);

    /// [optional] Runs what an instance needs while something waits for a completion, as a window handling its
    /// events; NULL for one that needs nothing.
    /// @param instance The owner's ref.
    void (*pump)(void *instance);

    /// [optional] Sends every line the implementation's library logs to @p callback; NULL for one that does not
    /// log. Parts of one library share it, and a caller calls each distinct setter once.
    /// @param callback [callback,optional] Receives each line.
    /// @param ctx [context] Handed to @p callback unchanged.
    void (*set_log)(ke_log_callback callback, void *ctx);
} ke_part;

#ifdef __cplusplus
}
#endif

#endif
