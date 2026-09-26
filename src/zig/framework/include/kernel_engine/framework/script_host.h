#ifndef KERNEL_ENGINE_FRAMEWORK_SCRIPT_HOST_H_
#define KERNEL_ENGINE_FRAMEWORK_SCRIPT_HOST_H_

#include <stdbool.h>
#include <stdint.h>

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ke_ecs.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Keeps the association between an entity and the object a scripting runtime
    /// bound to it, and answers the questions a script asks about the scene around
    /// itself.
    ///
    /// ke_scene_loader already calls out to a language to build that object, and
    /// then forgets it: the loader learns a type name, hands over an entity, and
    /// the binding lives on in whatever map the language happened to keep. That map
    /// is engine state wearing a language's clothes — every runtime that wants to
    /// host scripts rebuilds it, and none of them can see each other's nodes.
    ///
    /// Holding it here is what makes the association language-neutral. The instance
    /// is an opaque pointer this host never dereferences; whose heap it lives in is
    /// the binding runtime's business, and two runtimes can bind nodes in the same
    /// scene without either one owning the map.
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
        /// Anything unproven belongs here: over-declaring costs parallelism, while
        /// under-declaring corrupts memory.
        KE_SCRIPT_REACH_ANY = 1,
    } ke_script_reach;

    /// Why a resolve answered the way it did. Without it "no node answers" and "two
    /// nodes answer" arrive as the same invalid entity, and a binding runtime can only
    /// tell its author the borrow found nothing — sending them to look for a node that
    /// is there twice.
    typedef enum ke_script_resolve
    {
        /// Exactly one entity answered, and it is the one returned.
        KE_SCRIPT_RESOLVE_FOUND = 0,
        /// Nothing answered. The borrow names a node that is not there.
        KE_SCRIPT_RESOLVE_NONE = 1,
        /// More than one answered, so none was returned. Naming the borrow settles it.
        KE_SCRIPT_RESOLVE_AMBIGUOUS = 2,
    } ke_script_resolve;

    /// [borrow_kinds] Where a borrow looks for the node it names. One question asked
    /// three ways rather than three questions: a borrow is always "an instance of
    /// this type, optionally by this name", and only the region searched differs.
    typedef enum ke_script_borrow
    {
        /// Below the borrower, depth-first. A node reaches a grandchild it names
        /// without every level in between forwarding it.
        KE_SCRIPT_BORROW_DESCENDANT = 0,
        /// The nearest above the borrower. An ancestor chain has one node per level,
        /// so this is the one reach that can never answer ambiguous.
        KE_SCRIPT_BORROW_ANCESTOR = 1,
        /// Anywhere the type is bound, ignoring the borrower's position. What a node
        /// reporting to a sibling subsystem needs, and the reason this is asked here
        /// rather than by a binding walking every node it knows about.
        KE_SCRIPT_BORROW_ANYWHERE = 2,
    } ke_script_borrow;

    struct ke_script_host
    {
        void *handle;

        /// Registers a script type under `name`, described by the components its
        /// instances carry and how far its behaviour reaches. Registering the same
        /// name twice returns the existing id when the description matches and
        /// fails when it does not — two languages naming one type differently would
        /// otherwise disagree about what a node in a scene file is.
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

        /// [try] Resolves a type by name without registering it, so a scene naming
        /// a type nobody declared fails instead of inventing an empty one.
        /// @param name [utf8]
        bool (*type_lookup)(struct ke_script_host *self,
                            const char            *name,
                            ke_script_type_id     *out_id);

        /// The components a registered type's instances carry, in registration
        /// order. This is what a host turns into the type's query and access list,
        /// so it is read back rather than re-derived by each binding.
        const ke_component_id *(*type_components)(struct ke_script_host *self,
                                                  ke_script_type_id      type,
                                                  uint32_t              *out_count);

        /// How far the registered type's behaviour reaches. KE_SCRIPT_REACH_ANY for
        /// an unknown id, because refusing to parallelise something unknown is the
        /// safe direction.
        ke_script_reach (*type_reach)(struct ke_script_host *self, ke_script_type_id type);

        /// Binds `instance` to `entity` as an instance of `type`. The pointer is
        /// stored and never dereferenced. Binding an entity that already carries an
        /// instance fails rather than replacing it silently, since the previous
        /// binding's owner would then never learn its object was dropped.
        /// @param instance [rooted:entity]
        bool (*bind)(struct ke_script_host *self,
                     ke_entity              entity,
                     ke_script_type_id      type,
                     void                  *instance,
                     ke_error             **out_error);

        /// [unroots:entity] Drops the binding for `entity`, if any. The instance
        /// itself is the binding runtime's to release.
        void (*unbind)(struct ke_script_host *self, ke_entity entity);

        /// [try] The instance bound to `entity`. False when none is, which is the
        /// normal answer rather than a failure: an entity a scene made without a
        /// script, or one another runtime owns, matches the same queries.
        /// @param out_type [out]
        /// @param out_instance [out]
        bool (*instance_of)(struct ke_script_host *self,
                            ke_entity              entity,
                            ke_script_type_id     *out_type,
                            void                 **out_instance);

        /// How many entities are currently bound as instances of `type`. What lets
        /// a host tell "this type had nothing to do" apart from "this type's query
        /// stopped matching", which are indistinguishable from inside the body.
        uint32_t (*instance_count)(struct ke_script_host *self, ke_script_type_id type);

        /// The entities bound as instances of `type`, in binding order. What lets a
        /// binding runtime drive a type's instances without keeping a parallel list
        /// of its own — the list that only its own language can see, and that drifts
        /// from the bindings the moment anything else unbinds one.
        ///
        /// The slice belongs to the host and is invalidated by the next bind or
        /// unbind of that type, which is the same tick's structural change a caller
        /// already defers to the wave barrier.
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
