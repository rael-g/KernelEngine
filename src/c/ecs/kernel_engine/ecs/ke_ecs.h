#ifndef KERNEL_ENGINE_ECS_KE_ECS_H_
#define KERNEL_ENGINE_ECS_KE_ECS_H_

#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <kernel_engine/ecs/ecs.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /** A component tuple registered once and resolved into archetype segments. */
    /// [id]
    typedef uint64_t ke_query_id;
#define KE_QUERY_INVALID ((ke_query_id)0)

    /** How a query term's column is used. */
    typedef enum ke_ecs_access
    {
        KE_ECS_ACCESS_READ  = 1 << 0,
        KE_ECS_ACCESS_WRITE = 1 << 1,
    } ke_ecs_access;

    /// [value] One component a query matches and hands a column of, and how the column is used.
    typedef struct ke_ecs_query_term
    {
        ke_component_id component;
        ke_ecs_access   access; ///< Read, write, or both.
    } ke_ecs_query_term;

    /** [borrowed]
     * A query to register: the entities having every term's component and every `with`
     * component, and none of the `without` components.
     */
    typedef struct ke_ecs_query_desc
    {
        const ke_ecs_query_term *terms; ///< [array_of:term_count] One column each, in this order.
        uint32_t                 term_count;
        const ke_component_id   *with; ///< [optional,array_of:with_count] Required, handing no column.
        uint32_t                 with_count;
        const ke_component_id   *without; ///< [optional,array_of:without_count] Excluded.
        uint32_t                 without_count;
        /// Each resolve reports which segments changed since this query's previous resolve; such a
        /// query is never shared with another registration of the same description.
        bool track_changes;
    } ke_ecs_query_desc;

    /** [view]
     * One archetype's slice of a query match: the matched entities, plus one
     * column base pointer per query term in the order query_register received
     * them, each aligned 1:1 with `entities`. A tag term's column is NULL.
     * Pointers stay valid until the next structural change.
     */
    typedef struct ke_ecs_segment
    {
        const ke_entity *entities; ///< [array_of:count] The entities this segment matched.
        size_t           count;
        void           **columns; ///< [array_of:column_count] One base pointer per query term.
        uint32_t         column_count;
        /// For a query tracking changes: never false when, since the query's previous resolve, an
        /// entity of the segment gained a component of one of its terms or had one written through
        /// a resolve or a command; it may be true without that, and is true on the first resolve.
        /// False for a query that does not track changes.
        bool             changed;
        /// [array_of:column_count] Per term, the component it matched: the pair a wildcard pair
        /// term matched, the term's own component otherwise.
        const ke_component_id *matched;
    } ke_ecs_segment;

    /** A captured state of some components of a world, restored with ke_ecs.restore. */
    typedef struct ke_ecs_snapshot ke_ecs_snapshot;

    /// [id] What remembers the entities that lost one component, for ke_ecs.removals.
    typedef uint64_t ke_removal_tracker;

    /** One world: entity lifetime, component storage and queries. The ids, components and
     * queries of one ke_ecs mean nothing to another. */
    typedef struct ke_ecs
    {
        void *handle;

        /**
         * Creates a fresh entity with no components. Structural; single-threaded.
         * @param out_entity [out] Receives the entity; the null entity on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the backend refuses the call, its
         *         reason logged.
         */
        ke_result (*entity_create)(struct ke_ecs *self, ke_entity *out_entity);

        /**
         * Destroys an entity and all its components; an entity that is not alive is left
         * alone. Structural; single-threaded.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for the null entity or when the backend
         *         refuses the call, its reason logged.
         */
        ke_result (*entity_destroy)(struct ke_ecs *self, ke_entity entity);

        /**
         * Registers a component type by name, or returns the existing id if already registered.
         *
         * A repeated name with the same size, alignment and layout answers the same id. A repeated
         * name with another layout and a field table on both registrations migrates the data of
         * every entity and singleton by field name: a field of the same name and type is copied,
         * a new field takes the default of the table, a field that is gone is dropped; the id
         * stays. Without field tables a different size or alignment is refused.
         *
         * @param params [borrowed] The name, size, alignment and field table of the type.
         * @param out_cid [out] Receives the component's id; KE_COMPONENT_INVALID on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the params are missing, the alignment is
         *         not a power of two, or the type differs from the name's prior registration with
         *         no field table to migrate by, what disagrees being logged; KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*component_register)(struct ke_ecs              *self,
                                        const ke_component_params  *params,
                                        ke_component_id            *out_cid);

        /**
         * [try] Looks up a previously registered component by name.
         * @param name [borrowed,utf8] Component name to find.
         * @param out_meta [out] Receives the component's id, size, and field metadata.
         * @return false if no component of that name is registered.
         */
        bool (*component_lookup)(struct ke_ecs     *self,
                                 const char        *name,
                                 ke_component_meta *out_meta);

        /**
         * Attaches a component to an entity: its storage is zeroed, then seeded with the
         * defaults of the field table the component was registered with, on the first
         * attach; an entity that already has the component keeps its storage unchanged.
         * Structural; single-threaded.
         * @param out_data [out] Receives the storage, valid until the next structural change on
         *        this ecs; NULL for a tag, and on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an entity that is not alive, the null
         *         entity or component, or when the backend refuses the call, its reason logged.
         */
        ke_result (*component_add)(struct ke_ecs  *self,
                                   ke_entity       entity,
                                   ke_component_id component,
                                   void          **out_data);

        /**
         * Detaches a component from an entity; an entity that is not alive is left alone.
         * Structural; single-threaded.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for the null entity or component, or when
         *         the backend refuses the call, its reason logged.
         */
        ke_result (*component_remove)(struct ke_ecs  *self,
                                      ke_entity       entity,
                                      ke_component_id component);

        /**
         * Returns an entity's component storage, or NULL if it doesn't have that component.
         * The pointer is valid until the next structural change on this ecs.
         */
        void *(*component_get)(struct ke_ecs *self,
                               ke_entity      entity,
                               ke_component_id component);

        /** Byte size of a registered component's element; 0 for a tag or unknown cid. */
        size_t (*component_size)(struct ke_ecs *self, ke_component_id cid);

        /**
         * Writes @p value into @p component at the place @p field describes, converted to the
         * field's type: an integer and a float convert to each other, a boolean to an integer, and
         * a vector widens or narrows to the field's width; a string is cut to the field's size and
         * stays NUL-terminated.
         * @param component [borrowed] The component's memory.
         * @param field     [borrowed] Where in the component, and of which type and size.
         * @param value     [borrowed] The value to write.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument, or for a value that does
         *         not convert to the field's type or a size the type cannot have, writing nothing.
         */
        ke_result (*component_field_write)(struct ke_ecs                 *self,
                                           void                          *component,
                                           const ke_component_field      *field,
                                           const ke_variant              *value);

        /**
         * Registers a query. A description equal to one registered before answers the id it got
         * then, unless it tracks changes.
         * @param desc [borrowed] The terms, the required and excluded components, and whether
         *        changes are tracked.
         * @param out_query [out] Receives the query; KE_QUERY_INVALID on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for no terms, a term with no access or an
         *         unknown one, more terms and filters than the backend's queries hold, or a query
         *         the backend refuses, its reason logged; KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*query_register)(struct ke_ecs           *self,
                                    const ke_ecs_query_desc *desc,
                                    ke_query_id             *out_query);

        /**
         * Resolves a query into archetype segments. MUST run single-threaded, before
         * a parallel wave; afterwards the segments are plain memory touching no
         * backend state.
         * @param out_segments [out,array_of:max_segments] Receives the matched segments.
         * @param max_segments Capacity of out_segments.
         * Counts the columns of the query's written terms as written, for change tracking.
         * @param out_columns [out] Backing store of the segments' columns: segment i's columns
         *        are the term_count entries starting at index i * term_count, term_count being
         *        that of the description the query was registered with.
         * @param out_matched [out] Backing store of the segments' matched components, laid out as
         *        @p out_columns.
         * @param out_count [out] Receives how many segments the query matches; above
         *        max_segments, out_segments holds only the first max_segments of them, and the
         *        others keep their changes for the next resolve; zero on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown query, missing output arrays
         *         or a zero capacity, or when the backend refuses the call, its reason logged.
         */
        ke_result (*query_resolve)(struct ke_ecs   *self,
                                   ke_query_id       query,
                                   ke_ecs_segment   *out_segments,
                                   size_t            max_segments,
                                   void            **out_columns,
                                   ke_component_id  *out_matched,
                                   size_t           *out_count);

        /**
         * Reserves an entity id, callable concurrently from any wave thread —
         * the one entity operation that is. The id is usable immediately as a
         * reference; the entity itself appears in the world when component_add
         * first runs for it, at the wave barrier.
         *
         * An implementation may not satisfy this by forwarding to entity_create,
         * which is single-threaded.
         * The implementation may replace a reserved id when the commands recorded with it are
         * applied, rewriting every ENTITY field that holds it; a caller does not rely on the
         * number before then.
         * @param out_entity [out] Receives the id; the null entity on failure.
         * @return KE_OK; KE_RESULT_OUT_OF_MEMORY when every id the implementation can reserve
         *         was handed out.
         */
        ke_result (*entity_reserve)(struct ke_ecs *self, ke_entity *out_entity);

        /**
         * Brings a reserved id into the world, so an entity that never receives a
         * component still exists. Structural; single-threaded. A no-op for an id
         * that is already alive or was never reserved.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for the null entity or when the backend
         *         refuses the call, its reason logged; KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*entity_materialize)(struct ke_ecs *self, ke_entity entity);

        /**
         * Gives the world one value of a component, matched by no query: its storage is zeroed,
         * then seeded with the defaults of the component's field table, the first time; a
         * singleton that exists keeps its storage. Structural; single-threaded.
         * @param out_data [out] Receives the storage, valid until the next structural change on
         *        this ecs; NULL for a tag, and on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for the null or an unknown component, or
         *         when the backend refuses the call, its reason logged.
         */
        ke_result (*singleton_add)(struct ke_ecs  *self,
                                   ke_component_id component,
                                   void          **out_data);

        /**
         * Returns the world's value of a component, or NULL if it has none. The pointer is valid
         * until the next structural change on this ecs.
         */
        void *(*singleton_get)(struct ke_ecs *self, ke_component_id component);

        /**
         * Takes a component's value from the world; a component without one is left alone.
         * Structural; single-threaded.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for the null component or when the backend
         *         refuses the call, its reason logged.
         */
        ke_result (*singleton_remove)(struct ke_ecs *self, ke_component_id component);

        /**
         * The component id of a pair: @p relation applied to @p target. A pair is added, removed,
         * read and queried as any component, holding the relation's storage. With
         * KE_ENTITY_WILDCARD as target the id matches every pair of the relation, in a query term,
         * a with or a without alone.
         * @param out_cid [out] Receives the pair's id; KE_COMPONENT_INVALID on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown relation or the null target;
         *         KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*pair)(struct ke_ecs *self, ke_component_id relation, ke_entity target,
                          ke_component_id *out_cid);
        /**
         * [try] The relation and the target of a pair's id.
         * @param out_relation [out] Receives the relation.
         * @param out_target [out] Receives the target, KE_ENTITY_WILDCARD for a wildcard pair.
         * @return false for an id that is not a pair.
         */
        bool (*pair_parts)(struct ke_ecs *self, ke_component_id pair, ke_component_id *out_relation,
                           ke_entity *out_target);
        /**
         * Starts remembering the entities that lose @p component, by removal or by being
         * destroyed. Single-threaded.
         * @param out_tracker [out] Receives the tracker.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for the null or an unknown component;
         *         KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*removal_track)(struct ke_ecs *self, ke_component_id component,
                                   ke_removal_tracker *out_tracker);
        /**
         * Hands out the entities that lost the tracker's component since the previous call, and
         * forgets them. Single-threaded.
         * @param out_entities [out,array_of:capacity] Receives the entities.
         * @param out_count [out] Receives how many were lost; above @p capacity, the rest stay for
         *        the next call.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown tracker or a null output.
         */
        ke_result (*removals)(struct ke_ecs *self, ke_removal_tracker tracker, ke_entity *out_entities,
                              size_t capacity, size_t *out_count);
        /**
         * The components an entity has, pairs included.
         * @param out_cids [out,array_of:capacity] Receives the components.
         * @param out_count [out] Receives how many it has; above @p capacity only the first fit.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an entity that is not alive or a null output.
         */
        ke_result (*entity_components)(struct ke_ecs *self, ke_entity entity, ke_component_id *out_cids,
                                       size_t capacity, size_t *out_count);
        /**
         * The components registered in the world.
         * @param out_cids [out,array_of:capacity] Receives the components.
         * @param out_count [out] Receives how many are registered; above @p capacity only the
         *        first fit.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null output.
         */
        ke_result (*components)(struct ke_ecs *self, ke_component_id *out_cids, size_t capacity,
                                size_t *out_count);
        /**
         * Captures the world's entities and the values of the listed components and of their
         * singletons. Single-threaded.
         * @param components [borrowed,array_of:component_count] What the snapshot holds the values of.
         * @param out_snapshot [out] Receives the snapshot, freed with snapshot_free.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown component;
         *         KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*snapshot)(struct ke_ecs *self, const ke_component_id *components,
                              uint32_t component_count, ke_ecs_snapshot **out_snapshot);
        /**
         * Brings the world back to a snapshot: afterwards it behaves as when the snapshot was taken
         * for its entities, the ids later creations receive, and the components and singletons
         * the snapshot lists, and for nothing else. A handle a component holds comes back as the
         * number it was. Structural; single-threaded.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a snapshot of another world;
         *         KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*restore)(struct ke_ecs *self, const ke_ecs_snapshot *snapshot);
        /** Frees a snapshot; a null one is ignored. */
        void (*snapshot_free)(struct ke_ecs *self, ke_ecs_snapshot *snapshot);
    } ke_ecs;

    /// [owner]
    typedef struct ke_ecs_handle
    {
        ke_ecs *ref;
        void (*destroy)(ke_ecs *self);
    } ke_ecs_handle;

/// The values an ECS is created with, whatever its implementation, each applied as given.
typedef struct ke_ecs_config
{
    /// How many ids entity_reserve may hand out before the world issues any of its own; entity_reserve
    /// fails as out of memory once they are spent. Raise it for a world whose systems spawn heavily.
    uint32_t reserved_id_capacity;
} ke_ecs_config;

#ifdef __cplusplus
}
#endif

#endif
