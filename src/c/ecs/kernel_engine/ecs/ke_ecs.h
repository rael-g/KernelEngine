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
    } ke_ecs_segment;

    /** Entity lifetime and component storage. */
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
         * A repeated name must describe the same size, alignment and layout as its first
         * registration. With `fields` the layouts are compared field by field; without them,
         * only the size and the alignment are compared.
         *
         * @param params [borrowed] The name, size, alignment and field table of the type.
         * @param out_cid [out] Receives the component's id; KE_COMPONENT_INVALID on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT when the params are missing, the alignment is
         *         not a power of two, or the type conflicts with the name's prior registration,
         *         what disagrees being logged; KE_RESULT_OUT_OF_MEMORY.
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
         * Registers a query over a component tuple (entities matching ALL cids).
         * @param cids [borrowed,array_of:cid_count] Component tuple to match.
         * @param cid_count Number of components in the tuple.
         * @param out_query [out] Receives the query; KE_QUERY_INVALID on failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an empty tuple, one with more terms than
         *         the backend's queries hold, or one the backend refuses, its reason logged;
         *         KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*query_register)(struct ke_ecs         *self,
                                    const ke_component_id *cids,
                                    size_t                 cid_count,
                                    ke_query_id           *out_query);

        /**
         * Resolves a query into archetype segments. MUST run single-threaded, before
         * a parallel wave; afterwards the segments are plain memory touching no
         * backend state.
         * @param out_segments [out,array_of:max_segments] Receives the matched segments.
         * @param max_segments Capacity of out_segments.
         * @param out_columns [out] Backing store of the segments' columns: segment i's columns
         *        are the cid_count entries starting at index i * cid_count, cid_count being
         *        the length of the tuple the query was registered with.
         * @param out_count [out] Receives how many segments the query matches; above
         *        max_segments, out_segments holds only the first max_segments of them; zero on
         *        failure.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for an unknown query, missing output arrays
         *         or a zero capacity, or when the backend refuses the call, its reason logged.
         */
        ke_result (*query_resolve)(struct ke_ecs   *self,
                                   ke_query_id       query,
                                   ke_ecs_segment   *out_segments,
                                   size_t            max_segments,
                                   void            **out_columns,
                                   size_t           *out_count);

        /**
         * Reserves an entity id, callable concurrently from any wave thread —
         * the one entity operation that is. The id is usable immediately as a
         * reference; the entity itself appears in the world when component_add
         * first runs for it, at the wave barrier.
         *
         * An implementation may not satisfy this by forwarding to entity_create,
         * which is single-threaded.
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

    } ke_ecs;

    /// [owner]
    typedef struct ke_ecs_handle
    {
        ke_ecs *ref;
        void (*destroy)(ke_ecs *self);
    } ke_ecs_handle;

#ifdef __cplusplus
}
#endif

#endif
