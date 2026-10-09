#ifndef KERNEL_ENGINE_FRAMEWORK_SCRIPT_HOST_H_
#define KERNEL_ENGINE_FRAMEWORK_SCRIPT_HOST_H_

#include <stdbool.h>
#include <stdint.h>

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ke_ecs.h>
#include <kernel_engine/ecs/commands.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Keeps the association between an entity and the object a scripting runtime
    /// bound to it, and answers the questions a script asks about the scene around
    /// itself.
    ///
    /// The instance is an opaque pointer this host stores and never dereferences.
    /// Several binding runtimes may bind entities in the same scene.
    typedef struct ke_script_host ke_script_host;

    /// Identifies a registered script type. Zero is never a valid id, so a zeroed
    /// struct reads as "no type" rather than as the first type registered.
    typedef uint32_t ke_script_type_id;

#define KE_SCRIPT_TYPE_NONE 0u

    /// How far one instance's behaviour reaches, which is what decides whether the
    /// runtime may run a type's instances as concurrent slices.
    typedef enum ke_script_reach
    {
        /// Touches only the entity it is bound to. Two instances are two entities,
        /// so their work cannot overlap.
        KE_SCRIPT_REACH_SELF = 0,
        /// Reaches entities it was not handed — a borrow, a lookup by name, a query.
        /// Anything unproven belongs here.
        KE_SCRIPT_REACH_ANY = 1,
    } ke_script_reach;

    /// Reports why a resolve answered the way it did.
    typedef enum ke_script_resolve
    {
        /// Exactly one entity answered, and it is the one returned.
        KE_SCRIPT_RESOLVE_FOUND = 0,
        /// Nothing answered. The borrow names a node that is not there.
        KE_SCRIPT_RESOLVE_NONE = 1,
        /// More than one answered, so none was returned.
        KE_SCRIPT_RESOLVE_AMBIGUOUS = 2,
    } ke_script_resolve;

    /// [borrow_kinds] Where a borrow looks for the node it names. A borrow is always
    /// an instance of a type, optionally with a name; only the region searched differs.
    typedef enum ke_script_borrow
    {
        /// Below the borrower, depth-first.
        KE_SCRIPT_BORROW_DESCENDANT = 0,
        /// The nearest above the borrower. This is the only reach that never answers
        /// ambiguous.
        KE_SCRIPT_BORROW_ANCESTOR = 1,
        /// Anywhere the type is bound, ignoring the borrower's position.
        KE_SCRIPT_BORROW_ANYWHERE = 2,
    } ke_script_borrow;

    struct ke_script_host
    {
        void *handle;

        /// Registers a script type under `name`, described by the components its
        /// instances carry and how far its behaviour reaches. Registering the same
        /// name twice returns the existing id when the description matches and
        /// fails when it does not.
        /// @param name [utf8]
        /// @param components [array_of:component_count]
        /// @param out_id [out]
        bool (*register_type)(struct ke_script_host *self,
                              const char            *name,
                              const ke_component_id *components,
                              uint32_t               component_count,
                              ke_script_reach        reach,
                              ke_script_type_id     *out_id,
                              ke_error             **out_error);

        /// [try] Resolves a type by name without registering it. An undeclared name fails.
        /// @param name [utf8]
        /// @param out_id [out]
        bool (*type_lookup)(struct ke_script_host *self,
                            const char            *name,
                            ke_script_type_id     *out_id);

        /// The components a registered type's instances carry, in registration
        /// order.
        /// @param out_count [out]
        /// @return [array_of:out_count]
        const ke_component_id *(*type_components)(struct ke_script_host *self,
                                                  ke_script_type_id      type,
                                                  uint32_t              *out_count);

        /// How far the registered type's behaviour reaches. KE_SCRIPT_REACH_ANY for
        /// an unknown id.
        ke_script_reach (*type_reach)(struct ke_script_host *self, ke_script_type_id type);

        /// Binds `instance` to `entity` as an instance of `type`. The pointer is
        /// stored and never dereferenced. Binding an entity that already carries an
        /// instance fails rather than replacing it.
        /// @param instance [rooted:entity]
        bool (*bind)(struct ke_script_host *self,
                     ke_entity              entity,
                     ke_script_type_id      type,
                     void                  *instance,
                     ke_error             **out_error);

        /// [unroots:entity] Drops the binding for `entity`, if any. The instance
        /// itself is the binding runtime's to release.
        void (*unbind)(struct ke_script_host *self, ke_entity entity);

        /// [idiom] Records bind into `commands`; the binding takes effect when `commands`
        /// is applied. A bind that fails at that point is dropped.
        /// @param instance [rooted:entity]
        /// @param commands [ctx]
        bool (*bind_deferred)(struct ke_script_host *self,
                              ke_entity              entity,
                              ke_script_type_id      type,
                              void                  *instance,
                              ke_ecs_commands       *commands,
                              ke_error             **out_error);

        /// [idiom] Records unbind into `commands`; the binding is dropped when `commands`
        /// is applied.
        /// @param commands [ctx]
        bool (*unbind_deferred)(struct ke_script_host *self,
                                ke_entity              entity,
                                ke_ecs_commands       *commands,
                                ke_error             **out_error);

        /// [try] The instance bound to `entity`. False when none is, which is a normal
        /// answer, not a failure.
        /// @param out_type [out]
        /// @param out_instance [out,rooted]
        bool (*instance_of)(struct ke_script_host *self,
                            ke_entity              entity,
                            ke_script_type_id     *out_type,
                            void                 **out_instance);

        /// How many entities are currently bound as instances of `type`.
        uint32_t (*instance_count)(struct ke_script_host *self, ke_script_type_id type);

        /// The entities bound as instances of `type`, in binding order.
        ///
        /// The slice belongs to the host and is invalidated by the next bind or
        /// unbind of that type.
        /// @param out_count [out]
        /// @return [array_of:out_count]
        const ke_entity *(*instances)(struct ke_script_host *self,
                                      ke_script_type_id      type,
                                      uint32_t              *out_count);

        /// [borrows] The entity `owner` borrows: an instance of `type` found within
        /// `reach`. `name` narrows it to a node of that name; empty matches on type
        /// alone, and answers ambiguous when two candidates qualify rather than
        /// picking one. `out_why` says which of the two an invalid answer was, and
        /// may be NULL.
        /// @param name [utf8]
        /// @param reach [enum:ke_script_borrow]
        /// @param out_why [out,enum:ke_script_resolve]
        ke_entity (*resolve)(struct ke_script_host *self,
                             ke_entity              owner,
                             ke_script_type_id      type,
                             const char            *name,
                             ke_script_borrow       reach,
                             ke_script_resolve     *out_why);
    };

    /// Owner wrapper: destroy releases the type table and the bindings. The
    /// instances are not touched — this host never owned them.
    typedef struct ke_script_host_handle
    {
        ke_script_host *ref;
        void (*destroy)(ke_script_host *self);
    } ke_script_host_handle;

#ifdef __cplusplus
}
#endif

#endif
