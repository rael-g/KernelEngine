#ifndef KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_H_
#define KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/commands.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct ke_node_ctx ke_node_ctx;

    /// One call of a behaviour over the nodes of its type. The body walks them with
    /// next, which points self and fields at each node in turn; an on handler walks every
    /// pair of a node and an event, with event pointing at the event.
    /// @param ctx       What the body works with for the duration of the call.
    /// @param user_data [context] The desc's user_data.
    /// @return KE_OK, or the code of the work it could not finish; the tick fails with it.
    typedef ke_result (*ke_node_behaviour_fn)(ke_node_ctx *ctx, void *user_data);

    /// What a behaviour is given. Behaviours run one at a time, never two at once, so a body
    /// may read any node; it changes structure (a node, a component, an event) only through
    /// the calls that record into `commands`, applied after the body returns.
    struct ke_node_ctx
    {
        void *handle;

        /// The node next moved to; KE_ENTITY_INVALID before the first call of next.
        ke_entity self;

        /// The node's own fields, the struct its type was registered with; NULL for a type
        /// without fields.
        void *fields;

        /// The event an on handler is delivering; NULL in every other behaviour.
        const void *event;

        /// Seconds since the previous tick, or the fixed timestep in fixed_update.
        float dt;

        /// The queue structural changes are recorded into.
        ke_ecs_commands *commands;

        /// Moves to the next node, or the next pair of a node and an event.
        /// @return false when there is none left.
        bool (*next)(ke_node_ctx *self);

        /// One of the node's components: its fields or one its type names in `with`.
        /// @return The component's memory for the current node, NULL for a component the type
        ///         does not carry.
        void *(*get)(ke_node_ctx *self, ke_component_id cid);

        /// The node's parent, KE_ENTITY_INVALID for a node at the root.
        ke_entity (*parent)(ke_node_ctx *self, ke_entity node);

        /// The child of @p node named @p name, KE_ENTITY_INVALID when it has none.
        /// @param name [utf8]
        ke_entity (*child)(ke_node_ctx *self, ke_entity node, const char *name);

        /// The value of an axis action, 0 without input actions.
        float (*axis)(ke_node_ctx *self, int32_t action);

        /// Whether a button action was pressed this tick, false without input actions.
        bool (*pressed)(ke_node_ctx *self, int32_t action);

        /// Records a node of @p type named @p name under @p parent, its fields and the
        /// components its type names in `with` holding their declared defaults.
        /// @param name   [utf8]
        /// @param parent KE_ENTITY_INVALID places it at the root.
        /// @param out_node [out] Usable as a reference at once; the node exists once the commands
        ///                 are applied.
        /// @return KE_OK; KE_RESULT_NOT_FOUND for a type never registered, or the queue's code.
        ke_result (*spawn)(ke_node_ctx *self, ke_component_id type, const char *name, ke_entity parent, ke_entity *out_node);

        /// Records the destruction of @p node and its descendants.
        /// @return KE_OK, or the queue's code.
        ke_result (*destroy)(ke_node_ctx *self, ke_entity node);

        /// Records @p data as an event of type @p event, delivered to the on handlers of the
        /// PostUpdate of this tick that run after it is applied, and gone at the next PreUpdate.
        /// @param data [array_of:size] Copied.
        /// @return KE_OK; KE_RESULT_NOT_FOUND for an event never registered,
        ///         KE_RESULT_INVALID_ARGUMENT for a size that is not the event's, or the queue's code.
        ke_result (*raise)(ke_node_ctx *self, ke_component_id event, const void *data, size_t size);
    };

    /// One event a node type handles, and the behaviour that handles it.
    typedef struct ke_node_handler
    {
        ke_component_id      event;
        ke_node_behaviour_fn on;
    } ke_node_handler;

    /// A node type: its name, its own fields, the components its nodes also carry, and its
    /// behaviours.
    typedef struct ke_node_type_desc
    {
        /// [utf8] The type's name; its nodes carry a tag registered as `node.<name>`.
        const char *name;

        /// [borrowed, default:none] The type's own fields, registered as a component; NULL for a
        /// type made only of the components it names in `with`.
        const ke_component_params *fields;

        /// [array_of:with_count, utf8, default:empty] Names of registered components every
        /// node of the type carries beside its fields.
        const char *const *with;
        uint32_t           with_count;

        /// [closure:user_data, default:none] Runs once per node, in the PreUpdate after the
        /// node is created, before its first update.
        ke_node_behaviour_fn ready;

        /// [closure:user_data, default:none] Runs every tick, in Update.
        ke_node_behaviour_fn update;

        /// [closure:user_data, default:none] Runs every fixed step, in FixedUpdate.
        ke_node_behaviour_fn fixed_update;

        /// [array_of:on_count, default:empty] Runs in PostUpdate for each node and each event
        /// of the handler's type raised this tick.
        const ke_node_handler *on;
        uint32_t               on_count;

        /// [context] Forwarded to every behaviour.
        void *user_data;
    } ke_node_type_desc;

    /// Node types and the events between them: each behaviour of a registered type runs as a
    /// system of its phase over the nodes of the type, one behaviour at a time. A type named
    /// `node`, with no fields and no components, is registered from the start.
    typedef struct ke_node_types
    {
        void *handle;

        /// Registers a node type and the systems of its behaviours.
        /// @param desc [borrowed] Read during the call; the field table and the names it points
        ///             at must outlive the node types.
        /// @param out_type [out] Receives the id of the type's tag.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null or nameless desc, fields of zero
        ///         size or a behaviour-less handler; KE_RESULT_NOT_FOUND for a `with` name or a handler's
        ///         event never registered; the ecs's or the runtime's code when it refuses.
        ke_result (*register_type)(struct ke_node_types *self, const ke_node_type_desc *desc, ke_component_id *out_type);

        /// Registers an event type.
        /// @param event [borrowed] Its name, size and field table.
        /// @param out_event [out] Receives the event's component id.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null or nameless event, or the ecs's code.
        ke_result (*register_event)(struct ke_node_types *self, const ke_component_params *event, ke_component_id *out_event);

        /// Records a node of @p type named @p name under @p parent into @p commands, its fields
        /// and the components its type names in `with` holding their declared defaults. The one
        /// way a node is created: a behaviour's ctx->spawn is this call with its own commands.
        /// @param commands The queue the node is recorded into.
        /// @param name     [utf8]
        /// @param parent   KE_ENTITY_INVALID places it at the root.
        /// @param out_node [out] Usable as a reference at once; the node exists once the commands
        ///                 are applied.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for null commands; KE_RESULT_NOT_FOUND for a
        ///         type never registered, or the queue's code.
        ke_result (*spawn)(struct ke_node_types *self, ke_ecs_commands *commands, ke_component_id type, const char *name, ke_entity parent, ke_entity *out_node);

        /// Whether a node of @p type carries @p component: its fields or one its type names in
        /// `with`.
        /// @return false for a type never registered.
        bool (*carries)(struct ke_node_types *self, ke_component_id type, ke_component_id component);
    } ke_node_types;

    /// [owner]
    typedef struct ke_node_types_handle
    {
        ke_node_types *ref;
        void (*destroy)(ke_node_types *self);
    } ke_node_types_handle;

/** Moves @p ctx to each node in turn, with @p var pointing at the node's fields as @p type. */
#define KE_FOR_EACH_NODE(ctx, type, var) \
    for (type *var = NULL; (ctx)->next(ctx) && ((var = (type *)(ctx)->fields), 1);)

#ifdef __cplusplus
}
#endif

#endif
