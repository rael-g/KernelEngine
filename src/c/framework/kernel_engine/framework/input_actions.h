#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_

#include <kernel_engine/result/result.h>
#include <kernel_engine/input/key.h>
#include <kernel_engine/input/snapshot.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef enum ke_action_type
    {
        KE_ACTION_TYPE_BUTTON = 0,
        KE_ACTION_TYPE_AXIS1D = 1,
        KE_ACTION_TYPE_AXIS2D = 2,
        KE_ACTION_TYPE_AXIS3D = 3,
    } ke_action_type;

    /** [interface] Named actions grouped in maps, bound to keys and mouse buttons, evaluated once
     * per frame against an input snapshot and polled. Maps are evaluated from the highest priority
     * down, ties in the order they were added; a key or mouse button bound in an enabled map is
     * not seen by any map evaluated after it. The actions of a disabled map are inactive. */
    typedef struct ke_input_actions
    {
        void *handle;

        /** Adds an enabled map after those already present.
         * @param name [utf8] Unique among the maps.
         * @param priority Higher is evaluated first.
         * @return The map's id; -1 for a null, empty or duplicated name, or when it cannot be stored. */
        int32_t (*add_map)(struct ke_input_actions *self, const char *name, int32_t priority);

        /** @param name [utf8]
         * @return The id of the map with that name; -1 when none has it. */
        int32_t (*get_map_id)(struct ke_input_actions *self, const char *name);

        /** Enables or disables a map from the next evaluation on.
         * @return KE_OK; KE_RESULT_NOT_FOUND for an id no map has. */
        ke_result (*set_map_enabled)(struct ke_input_actions *self, int32_t map_id, bool enabled);

        /** False for an id no map has. */
        bool (*is_map_enabled)(struct ke_input_actions *self, int32_t map_id);

        /** @param name [utf8]
         * @return The id of the action with that name, in any map; -1 when none has it. */
        int32_t (*get_action_id)(struct ke_input_actions *self, const char *name);

        /** Adds an action to a map.
         * @param name [utf8] Unique among the actions of every map.
         * @return The action's id; -1 for an id no map has, a null, empty or duplicated name, or
         *         when it cannot be stored. */
        int32_t (*add_action)(struct ke_input_actions *self, int32_t map_id, const char *name,
                              ke_action_type type);

        /** Adds a key binding to an action.
         * @return KE_OK; KE_RESULT_NOT_FOUND for an id no action has, or KE_RESULT_OUT_OF_MEMORY. */
        ke_result (*bind_key)(struct ke_input_actions *self, int32_t action_id, ke_key key);

        /** Adds a mouse button binding to an action. Fails as bind_key does. */
        ke_result (*bind_mouse_button)(struct ke_input_actions *self, int32_t action_id,
                                       ke_mouse_button button);

        /** Adds a one-axis binding to an action, positive while @p positive is held and negative
         * while @p negative is. Fails as bind_key does. */
        ke_result (*bind_key_pair)(struct ke_input_actions *self, int32_t action_id,
                                   ke_key negative, ke_key positive);

        /** Adds a two-axis binding to an action: x is right minus left and y is up minus down.
         * Fails as bind_key does. */
        ke_result (*bind_key_quad)(struct ke_input_actions *self, int32_t action_id,
                                   ke_key up, ke_key down, ke_key left, ke_key right);

        /** Runs one frame of evaluation against @p snapshot, making each action's held state,
         * edges and axes current.
         * @return KE_OK, or KE_RESULT_INVALID_ARGUMENT for a null @p snapshot, which changes
         *         nothing. */
        ke_result (*evaluate)(struct ke_input_actions *self, const ke_input_snapshot *snapshot);

        bool (*is_action_down)(struct ke_input_actions *self, int32_t action_id);
        bool (*was_action_pressed)(struct ke_input_actions *self, int32_t action_id);
        bool (*was_action_released)(struct ke_input_actions *self, int32_t action_id);
        float (*get_axis1d)(struct ke_input_actions *self, int32_t action_id);
        /** @param out_x [out] @param out_y [out] */
        void  (*get_axis2d)(struct ke_input_actions *self, int32_t action_id,
                             float *out_x, float *out_y);
        /** @param out_x [out] @param out_y [out] @param out_z [out] */
        void  (*get_axis3d)(struct ke_input_actions *self, int32_t action_id,
                             float *out_x, float *out_y, float *out_z);

    } ke_input_actions;

    /// [owner]
    typedef struct ke_input_actions_handle
    {
        ke_input_actions *ref;
        void (*destroy)(ke_input_actions *self);
    } ke_input_actions_handle;

#ifdef __cplusplus
}
#endif

#endif
