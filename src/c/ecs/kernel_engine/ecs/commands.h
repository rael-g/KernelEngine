#ifndef KERNEL_ENGINE_ECS_COMMANDS_H_
#define KERNEL_ENGINE_ECS_COMMANDS_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_ecs_commands ke_ecs_commands;

/// A structural operation applied when the queue holding it is drained. `user` points at
/// the copy of the payload passed to defer; `ecs` is the live world. A failure is returned,
/// and the queue stops there: the operations recorded after it are dropped.
typedef ke_result (*ke_defer_fn)(ke_ecs *ecs, void *user);

/// A queue of structural mutations. Every operation records its intent and
/// returns; none changes the world while it runs. The queue is applied, in the order the
/// operations were recorded, by whoever owns it, and an operation's effect is not
/// observable before then. A caller needing a change visible at once uses ke_ecs, which
/// mutates immediately.
///
/// Recording never touches the world, so these operations may be called while other code
/// reads it. The queue is applied while nothing else runs.
///
/// An implementation that cannot accept an operation returns its code, logs the reason, and
/// leaves the queue unchanged: KE_RESULT_NOT_SUPPORTED in a phase that may not change
/// structure, KE_RESULT_OUT_OF_MEMORY when the queue cannot grow.
struct ke_ecs_commands {
    void *handle;

    /// Records the creation of an entity and answers the id it will have. The id can be
    /// named by later operations of this queue, and by any caller, at once; the entity
    /// itself exists once the queue is applied.
    /// @param out_entity [out] Receives the id; KE_ENTITY_INVALID on failure.
    ke_result (*spawn)(ke_ecs_commands *self, ke_entity *out_entity);

    /// Records giving `entity` the component `cid`, initialised from `size` bytes of
    /// `data`. The bytes are copied, so the caller's buffer need not outlive the call.
    /// `size` must equal the registered size of `cid`, or be 0 to attach the component without
    /// copying bytes into it.
    /// @param data [bytes_of:size]
    /// @return KE_RESULT_INVALID_ARGUMENT, besides the codes above, when `size` is neither 0 nor
    ///         the registered size of `cid`.
    ke_result (*attach)(ke_ecs_commands *self, ke_entity entity, ke_component_id cid, const void *data, size_t size);

    /// Records removing component `cid` from `entity`.
    ke_result (*detach)(ke_ecs_commands *self, ke_entity entity, ke_component_id cid);

    /// Records destroying `entity`.
    ke_result (*despawn)(ke_ecs_commands *self, ke_entity entity);

    /// [idiom] Records a structural operation for work the fixed verbs above cannot express. `fn`
    /// runs when the queue is applied, in order with the other operations.
    /// `user_size` bytes of `user` are copied, so the caller's buffer need not outlive
    /// the call.
    /// @param user [bytes_of:user_size]
    /// @return KE_RESULT_INVALID_ARGUMENT, besides the codes above, for a null `fn`.
    ke_result (*defer)(ke_ecs_commands *self, ke_defer_fn fn, const void *user, size_t user_size);
};

#ifdef __cplusplus
}
#endif

#endif
