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

    struct ke_script_host
    {
        void *handle;

        /// Registers a script type under `name`, described by the components its
        /// instances carry and how far its behaviour reaches. Registering the same
        /// name twice returns the existing id when the description matches and
        /// fails when it does not — two languages naming one type differently would
        /// otherwise disagree about what a node in a scene file is.
        /// @param name [utf8]
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
        bool (*bind)(struct ke_script_host *self,
                     ke_entity              entity,
                     ke_script_type_id      type,
                     void                  *instance,
                     ke_error             **out_error);

        /// Drops the binding for `entity`, if any. The instance itself is the
        /// binding runtime's to release.
        void (*unbind)(struct ke_script_host *self, ke_entity entity);

        /// [try] The instance bound to `entity`. False when none is, which is the
        /// normal answer rather than a failure: an entity a scene made without a
        /// script, or one another runtime owns, matches the same queries.
        bool (*instance_of)(struct ke_script_host *self,
                            ke_entity              entity,
                            ke_script_type_id     *out_type,
                            void                 **out_instance);

        /// How many entities are currently bound as instances of `type`. What lets
        /// a host tell "this type had nothing to do" apart from "this type's query
        /// stopped matching", which are indistinguishable from inside the body.
        uint32_t (*instance_count)(struct ke_script_host *self, ke_script_type_id type);

        /// The entity below `entity` bound as an instance of `type`, searched
        /// depth-first. `name` narrows it to a node of that name; empty matches on
        /// type alone, and is ambiguous exactly when two candidates answer to it,
        /// which returns KE_ENTITY_INVALID rather than picking one.
        /// @param name [utf8]
        ke_entity (*resolve_descendant)(struct ke_script_host *self,
                                        ke_entity              entity,
                                        ke_script_type_id      type,
                                        const char            *name);

        /// The nearest entity above `entity` bound as an instance of `type`.
        /// @param name [utf8]
        ke_entity (*resolve_ancestor)(struct ke_script_host *self,
                                      ke_entity              entity,
                                      ke_script_type_id      type,
                                      const char            *name);
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
