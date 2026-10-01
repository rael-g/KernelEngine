#pragma once

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_ecs_commands ke_ecs_commands;

/// A structural operation applied when the queue holding it is drained. `user` points at
/// the copy of the payload passed to defer; `ecs` is the live world.
typedef void (*ke_defer_fn)(ke_ecs *ecs, void *user);

/// [interface] A queue of structural mutations. Every operation records its intent and
/// returns; none changes the world while it runs. The queue is applied, in the order the
/// operations were recorded, by whoever owns it, and an operation's effect is not
/// observable before then. A caller needing a change visible at once uses ke_ecs, which
/// mutates immediately.
///
/// Recording is what makes these operations callable from code that must not touch the
/// world: a system body running beside other systems records, and the runtime applies
/// every body's queue while nothing else runs.
///
/// An implementation that cannot accept an operation fails it with the reason in
/// `out_error` and leaves the queue unchanged.
struct ke_ecs_commands {
    void *handle;

    /// Records the creation of an entity and answers the id it will have. The id can be
    /// named by later operations of this queue, and by any caller, at once; the entity
    /// itself exists once the queue is applied.
    /// @return KE_ENTITY_INVALID when the operation could not be recorded.
    ke_entity (*spawn)(ke_ecs_commands *self, ke_error **out_error);

    /// Records giving `entity` the component `cid`, initialised from `size` bytes of
    /// `data`. The bytes are copied, so the caller's buffer need not outlive the call.
    /// `size` must equal the registered size of `cid`, or be 0 to attach the component without
    /// copying bytes into it.
    /// @param data [bytes_of:size]
    /// @return false when the operation could not be recorded.
    bool (*attach)(ke_ecs_commands *self, ke_entity entity, ke_component_id cid, const void *data, size_t size, ke_error **out_error);

    /// Records removing component `cid` from `entity`.
    /// @return false when the operation could not be recorded.
    bool (*detach)(ke_ecs_commands *self, ke_entity entity, ke_component_id cid, ke_error **out_error);

    /// Records destroying `entity`.
    /// @return false when the operation could not be recorded.
    bool (*despawn)(ke_ecs_commands *self, ke_entity entity, ke_error **out_error);

    /// Records a structural operation for work the fixed verbs above cannot express. `fn`
    /// runs when the queue is applied, in order with the other operations.
    /// `user_size` bytes of `user` are copied, so the caller's buffer need not outlive
    /// the call.
    /// @param user [bytes_of:user_size]
    /// @return false when the operation could not be recorded.
    bool (*defer)(ke_ecs_commands *self, ke_defer_fn fn, const void *user, size_t user_size, ke_error **out_error);
};

#ifdef __cplusplus
}
#endif
