#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>
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

    typedef void (*ke_input_action_event_func)(void *ctx, ke_input_action_event event);

    typedef struct ke_input_actions
    {
        void *handle;

        ke_result (*load)(struct ke_input_actions *self, const char *path, ke_error **out_error);

        int32_t (*get_action_id)(struct ke_input_actions *self, const char *name);

        int32_t (*add_action)(struct ke_input_actions *self, const char *name,
                              ke_action_type type);

        ke_result (*bind_key)(struct ke_input_actions *self, int32_t action_id, ke_key key, ke_error **out_error);

        ke_result (*bind_mouse_button)(struct ke_input_actions *self, int32_t action_id,
                                        ke_mouse_button button, ke_error **out_error);

        ke_result (*bind_key_pair)(struct ke_input_actions *self, int32_t action_id,
                                    ke_key negative, ke_key positive, ke_error **out_error);

        ke_result (*bind_key_quad)(struct ke_input_actions *self, int32_t action_id,
                                    ke_key up, ke_key down, ke_key left, ke_key right, ke_error **out_error);

        ke_result (*evaluate)(struct ke_input_actions *self,
                               const ke_input_snapshot    *snapshot,
                               ke_input_action_event_func  on_event,
                               void                       *event_ctx,
                               ke_error                  **out_error);

        bool  (*is_action_down)(struct ke_input_actions *self, int32_t action_id);
        bool  (*was_action_pressed)(struct ke_input_actions *self, int32_t action_id);
        bool  (*was_action_released)(struct ke_input_actions *self, int32_t action_id);
        float (*get_axis1d)(struct ke_input_actions *self, int32_t action_id);
        void  (*get_axis2d)(struct ke_input_actions *self, int32_t action_id,
                             float *out_x, float *out_y);
        void  (*get_axis3d)(struct ke_input_actions *self, int32_t action_id,
                             float *out_x, float *out_y, float *out_z);

        void (*destroy)(struct ke_input_actions *self);
    } ke_input_actions;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_
