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

    typedef enum ke_action_phase
    {
        KE_ACTION_PHASE_STARTED   = 1,
        KE_ACTION_PHASE_PERFORMED = 2,
        KE_ACTION_PHASE_CANCELED  = 3,
    } ke_action_phase;

    typedef struct ke_input_action_event
    {
        int32_t         action_id;
        ke_action_type  type;
        ke_action_phase phase;
        float           x, y, z;
    } ke_input_action_event;

    /** Reports one phase transition of one binding.
     * @param ctx   [context] Opaque context forwarded from the call that registered it.
     * @param event The transition, naming the action it belongs to. */
    typedef void (*ke_input_action_event_func)(void *ctx, ke_input_action_event event);

    typedef struct ke_input_actions
    {
        void *handle;

        /** Replaces every action with those of a TOML input file. An action type other than
         * Button, Axis1D, Axis2D or Axis3D, a binding of an unknown kind, a binding missing a
         * field, and a key or mouse button name the engine does not know each fail the load,
         * as an invalid argument, logging the action and the binding; a load that fails leaves
         * no actions. A file that cannot be opened fails as not found and one that does not parse
         * as KE_RESULT_IO.
         * @param path [utf8] */
        ke_result (*load)(struct ke_input_actions *self, const char *path);

        /** @param name [utf8] */
        int32_t (*get_action_id)(struct ke_input_actions *self, const char *name);

        /** @param name [utf8] */
        int32_t (*add_action)(struct ke_input_actions *self, const char *name,
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

        /** Runs one frame of binding evaluation against @p snapshot, updating polling
         * state and firing @p on_event for each phase transition. A null @p on_event
         * updates polling only.
         * @param on_event [closure:event_ctx]
         * @return KE_OK, or KE_RESULT_INVALID_ARGUMENT for a null @p snapshot, which changes
         *         nothing. */
        ke_result (*evaluate)(struct ke_input_actions *self,
                              const ke_input_snapshot    *snapshot,
                              ke_input_action_event_func  on_event,
                              void                       *event_ctx);

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
