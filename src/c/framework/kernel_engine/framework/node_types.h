#ifndef KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_H_
#define KERNEL_ENGINE_FRAMEWORK_NODE_TYPES_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/ecs/commands.h>
#include <kernel_engine/ecs/variant.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [borrowed] A component a spawned node starts with in place of its type's initial value.
    typedef struct ke_node_component
    {
        ke_component_id component; ///< One of the components the type carries.
        const void     *data;      ///< [array_of:size] The component's bytes, copied by the spawn.
        size_t          size;      ///< The component's registered size.
    } ke_node_component;

    /// [borrowed] A value a node spawned by names starts with in one field, named as a scene file names it.
    typedef struct ke_node_field_value
    {
        const char *component; ///< [utf8] The registered name of a component the type carries, its fields' by the type's name.
        const char *field;     ///< [utf8] The field's name in the component's field table.
        ke_variant  value;     ///< Converted to the field's type as a scene file's value is; a string names an enum value.
    } ke_node_field_value;

    /// [borrowed] A component every node of a type carries beside its fields, and how it is born.
    typedef struct ke_node_with
    {
        const char *name;         ///< [utf8] The registered component's name.
        const void *initial;      ///< [array_of:initial_size] The bytes each node starts with; none starts it zeroed.
        size_t      initial_size; ///< The component's registered size, or 0 to start it zeroed.
    } ke_node_with;

    typedef struct ke_node_ctx ke_node_ctx;

#define KE_ACTION_NAME_MAX 32

    /// An input action named by a node's fields and resolved the first time a behaviour reads it.
    /// A scene writes its name; zeroed memory is a reference not yet resolved.
    typedef struct ke_action_ref
    {
        /// [utf8] The action's name in the input action maps.
        char    name[KE_ACTION_NAME_MAX];
        /// The action's id once resolved; meaningful only while resolved is true.
        int32_t id;
        /// Whether id holds the result of looking the name up.
        bool    resolved;
    } ke_action_ref;

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

        /// [typed] The node's own fields, the struct its type was registered with; NULL for a type
        /// without fields.
        void *fields;

        /// [typed] The event an on handler is delivering; NULL in every other behaviour.
        const void *event;

        /// The type of `event`; KE_COMPONENT_INVALID in every other behaviour.
        ke_component_id event_type;

        /// Seconds since the previous tick, or the fixed timestep in fixed_update.
        float dt;

        /// The queue structural changes are recorded into.
        ke_ecs_commands *commands;

        /// Moves to the next node, or the next pair of a node and an event.
        /// @return false when there is none left.
        bool (*next)(ke_node_ctx *self);

        /// One of the node's components: its fields or one its type names in `with`.
        /// @return [typed] The component's memory for the current node, NULL for a component the type
        ///         does not carry.
        void *(*get)(ke_node_ctx *self, ke_component_id cid);

        /// Any node's component, the current node's or another's.
        /// @return [typed] The component's memory on @p node, NULL for a node that does not carry it.
        void *(*component)(ke_node_ctx *self, ke_entity node, ke_component_id cid);

        /// The node's parent, KE_ENTITY_INVALID for a node at the root.
        ke_entity (*parent)(ke_node_ctx *self, ke_entity node);

        /// The child of @p node named @p name, KE_ENTITY_INVALID when it has none.
        /// @param name [utf8]
        ke_entity (*child)(ke_node_ctx *self, ke_entity node, const char *name);

        /// The first child of @p node, KE_ENTITY_INVALID when it has none.
        ke_entity (*first_child)(ke_node_ctx *self, ke_entity node);

        /// The child after @p node under the same parent, KE_ENTITY_INVALID after the last.
        ke_entity (*next_sibling)(ke_node_ctx *self, ke_entity node);

        /// The nearest ancestor of @p node holding @p component, KE_ENTITY_INVALID when none does.
        ke_entity (*ancestor)(ke_node_ctx *self, ke_entity node, ke_component_id component);

        /// The value of an axis action, 0 without input actions or for a name no map holds.
        /// @param action [inout] Resolved by name on its first read, and kept resolved.
        float (*axis)(ke_node_ctx *self, ke_action_ref *action);

        /// Whether a button action was pressed this tick, false without input actions or for a
        /// name no map holds.
        /// @param action [inout] Resolved by name on its first read, and kept resolved.
        bool (*pressed)(ke_node_ctx *self, ke_action_ref *action);

        /// Records a node of @p type named @p name under @p parent, its fields and the
        /// components its type names in `with` holding their initial values.
        /// @param name   [utf8]
        /// @param parent KE_ENTITY_INVALID places it at the root.
        /// @param components [array_of:component_count, default:empty] Components the node starts
        ///                   with in place of its type's initial values.
        /// @param out_node [out] Usable as a reference at once; the node exists once the commands
        ///                 are applied.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a component the type does not carry or
        ///         one whose size is not its registered size;
        ///         KE_RESULT_NOT_FOUND for a type never registered, or the queue's code.
        ke_result (*spawn)(ke_node_ctx *self, ke_component_id type, const char *name, ke_entity parent,
                           const ke_node_component *components, uint32_t component_count, ke_entity *out_node);

        /// Records a node of the type named @p type, its components born from the type's initial
        /// values with each of @p values written over them by name; the way any language spawns
        /// any node type, an engine one or a game's, without its ids or its structs.
        /// @param type   [utf8] The name the type was registered under.
        /// @param name   [utf8]
        /// @param parent KE_ENTITY_INVALID places it at the root.
        /// @param values [array_of:value_count, default:empty] Written in order.
        /// @param out_node [out] Usable as a reference at once; the node exists once the commands
        ///                 are applied.
        /// @return KE_OK; KE_RESULT_NOT_FOUND for a type never registered;
        ///         KE_RESULT_INVALID_ARGUMENT for a component the type does not carry, a field the
        ///         component's table does not name, or a value the field cannot hold; the queue's code.
        ke_result (*spawn_named)(ke_node_ctx *self, const char *type, const char *name, ke_entity parent,
                                 const ke_node_field_value *values, uint32_t value_count, ke_entity *out_node);

        /// Records the destruction of @p node and its descendants.
        /// @return KE_OK, or the queue's code.
        ke_result (*destroy)(ke_node_ctx *self, ke_entity node);

        /// Points the scene slot nearest above the current node at the scene file @p path; the
        /// slot replaces its children on its next update.
        /// @param path [utf8] As a scene slot's path.
        /// @return KE_OK; KE_RESULT_NOT_FOUND when no scene slot holds the node;
        ///         KE_RESULT_INVALID_ARGUMENT for a null @p path or one longer than a slot holds.
        ke_result (*change_scene)(ke_node_ctx *self, const char *path);

        /// Records @p data as an event of type @p event, delivered to the on handlers of the
        /// PostUpdate of this tick that run after it is applied, and gone at the next PreUpdate.
        /// @param data [bytes_of:size] Copied.
        /// @return KE_OK; KE_RESULT_NOT_FOUND for an event never registered,
        ///         KE_RESULT_INVALID_ARGUMENT for a size that is not the event's, or the queue's code.
        ke_result (*raise)(ke_node_ctx *self, ke_component_id event, const void *data, size_t size);

        /// Asks the runtime for the program to end; the host stops once it reads the request.
        void (*exit)(ke_node_ctx *self);
    };

    /// [bag] A node type: its name, its own fields, the components its nodes also carry, and its
    /// behaviours.
    typedef struct ke_node_type_desc
    {
        /// [utf8] The type's name; its nodes carry a tag registered as `node.<name>`.
        const char *name;

        /// [default:0] The bytes of the type's own fields, registered as a component under the type's name;
        /// 0 for a type made only of the components it names in `with`.
        size_t fields_size;

        /// [default:0] The alignment of the fields, a power of two when `fields_size` is not 0.
        size_t fields_alignment;

        /// [array_of:field_count, default:empty] The fields' table, copied by the ecs.
        const ke_component_field *fields;
        uint32_t                  field_count;

        /// [array_of:initial_size, default:empty] The bytes copied into the fields of each node
        /// spawned; none starts them zeroed.
        const void *initial;

        /// `fields_size`, or 0 to start them zeroed.
        size_t initial_size;

        /// [array_of:with_count, default:empty] Registered components every node of the type
        /// carries beside its fields, each with the value it is born with.
        const ke_node_with *with;
        uint32_t            with_count;

        /// [closure:user_data, retained:return, default:none] Runs once per node, in the PreUpdate after the
        /// node is created, before its first update.
        ke_node_behaviour_fn ready;

        /// [closure:user_data, retained:return, default:none] Runs every tick, in Update.
        ke_node_behaviour_fn update;

        /// [closure:user_data, retained:return, default:none] Runs every fixed step, in FixedUpdate.
        ke_node_behaviour_fn fixed_update;

        /// [array_of:event_count, default:empty] The event types `on` handles.
        const ke_component_id *events;
        uint32_t               event_count;

        /// [closure:user_data, retained:return, default:none] Runs in PostUpdate for each node and
        /// each event raised this tick of a type in `events`; the ctx's `event_type` says which.
        ke_node_behaviour_fn on;

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
        /// @param desc [borrowed] Read during the call; `initial` and the field table are copied.
        /// @param out_type [out] Receives the id of the type's tag.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null or nameless desc, a table or initial bytes
        ///         without `fields_size`, `initial` without fields, an initial whose size is not its component's, or
        ///         events without `on`; KE_RESULT_NOT_FOUND for a `with` name or an event never
        ///         registered; the ecs's or the runtime's code when it refuses.
        ke_result (*register_type)(struct ke_node_types *self, const ke_node_type_desc *desc, ke_component_id *out_type);

        /// Registers an event type.
        /// @param event [borrowed] Its name, size and field table.
        /// @param out_event [out] Receives the event's component id.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null or nameless event, or the ecs's code.
        ke_result (*register_event)(struct ke_node_types *self, const ke_component_params *event, ke_component_id *out_event);

        /// Records a node of @p type named @p name under @p parent into @p commands, its fields
        /// and the components its type names in `with` holding their initial values. The one
        /// way a node is created: a behaviour's ctx->spawn is this call with its own commands.
        /// @param commands The queue the node is recorded into.
        /// @param name     [utf8]
        /// @param parent   KE_ENTITY_INVALID places it at the root.
        /// @param components [array_of:component_count, default:empty] Components the node starts
        ///                   with in place of its type's initial values.
        /// @param out_node [out] Usable as a reference at once; the node exists once the commands
        ///                 are applied.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for null commands, a component the type
        ///         does not carry or one whose size is not its registered size; KE_RESULT_NOT_FOUND for a type never registered, or the queue's code.
        ke_result (*spawn)(struct ke_node_types *self, ke_ecs_commands *commands, ke_component_id type, const char *name,
                           ke_entity parent, const ke_node_component *components, uint32_t component_count, ke_entity *out_node);

        /// Records into @p commands a node of the type named @p type with @p values written over
        /// its initial values, as a behaviour's ctx->spawn_named does.
        /// @param commands The queue the node is recorded into.
        /// @param type   [utf8]
        /// @param name   [utf8]
        /// @param parent KE_ENTITY_INVALID places it at the root.
        /// @param values [array_of:value_count, default:empty] Written in order.
        /// @param out_node [out] Usable as a reference at once.
        /// @return As ctx->spawn_named; KE_RESULT_INVALID_ARGUMENT for null commands.
        ke_result (*spawn_named)(struct ke_node_types *self, ke_ecs_commands *commands, const char *type, const char *name,
                                 ke_entity parent, const ke_node_field_value *values, uint32_t value_count, ke_entity *out_node);

        /// The id of the type registered under @p name.
        /// @param name [utf8] The name its desc gave, `node` for the base type.
        /// @param out_type [out] Receives the id; KE_COMPONENT_INVALID when none has the name.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p name or @p out_type;
        ///         KE_RESULT_NOT_FOUND for a name no type was registered under.
        ke_result (*find_type)(struct ke_node_types *self, const char *name, ke_component_id *out_type);

        /// The id of the component registered under @p name, an engine component named by its
        /// `KE_COMPONENT_NAME_*` constant or one the game registered.
        /// @param name [utf8]
        /// @param out_component [out] Receives the id; KE_COMPONENT_INVALID when none has the name.
        /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p name or @p out_component;
        ///         KE_RESULT_NOT_FOUND for a name no component was registered under.
        ke_result (*find_component)(struct ke_node_types *self, const char *name, ke_component_id *out_component);

        /// The bytes a node of @p type is born with in @p component.
        /// @return [borrowed] The component's registered size of bytes, valid while the node types
        ///         live; NULL when the type was never registered or does not carry the component.
        const void *(*initial)(struct ke_node_types *self, ke_component_id type, ke_component_id component);

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
