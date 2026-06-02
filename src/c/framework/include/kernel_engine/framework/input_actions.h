#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_

#include <kernel_engine/framework/types.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/input/snapshot.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // ── Action event ─────────────────────────────────────────────────────────

    // Mirrors ActionType in KernelEngine.Kernel.Abstractions (values must stay in sync).
    typedef enum ke_action_type
    {
        KE_ACTION_TYPE_BUTTON = 0,
        KE_ACTION_TYPE_AXIS1D = 1,
        KE_ACTION_TYPE_AXIS2D = 2,
        KE_ACTION_TYPE_AXIS3D = 3,
    } ke_action_type;

    // Mirrors ActionPhase (values must stay in sync).
    typedef enum ke_action_phase
    {
        KE_ACTION_PHASE_STARTED   = 1,
        KE_ACTION_PHASE_PERFORMED = 2,
        KE_ACTION_PHASE_CANCELED  = 3,
    } ke_action_phase;

    // Blittable event passed by value to the on_event callback.
    typedef struct ke_input_action_event
    {
        int32_t          action_id; // int cast of the game TEnum value
        ke_action_type   type;
        ke_action_phase  phase;
        float            x, y, z;  // axis values; unused fields are zero
    } ke_input_action_event;

    // ── Callback typedef ─────────────────────────────────────────────────────

    typedef void (*ke_input_action_event_func)(void *ctx, ke_input_action_event event);

    // ── Input actions contract ────────────────────────────────────────────────
    //
    // Language-agnostic vtable for the input action layer (Tier S — S4).
    // The C# Framework provides CSharpInputActions as the round-trip implementation.
    // A future C++ plugin will parse the .input TOML natively and evaluate bindings
    // against ke_input_snapshot without touching managed code.

    typedef struct ke_input_actions
    {
        void *handle; // opaque; owned by the implementation

        /// Load action bindings from a .input file (UTF-8 path). May be called more
        /// than once to hot-reload. Returns KE_ERROR_NOT_FOUND if path does not exist.
        ke_result (*load)(struct ke_input_actions *self, const char *path);

        /// Run one frame of dispatch. Samples all bindings against snapshot, updates
        /// action state, and calls on_event for each phase transition. on_event may be
        /// NULL (useful when the caller only wants to update polling state).
        ke_result (*evaluate)(struct ke_input_actions *self,
                              const ke_input_snapshot  *snapshot,
                              ke_input_action_event_func on_event,
                              void                     *event_ctx);

        // ── Polling ──────────────────────────────────────────────────────────

        /// True while the action's combined value is active this frame.
        bool  (*is_action_down)(struct ke_input_actions *self, int32_t action_id);

        /// True for exactly the first frame the action became active.
        bool  (*was_action_pressed)(struct ke_input_actions *self, int32_t action_id);

        /// True for exactly the first frame the action became inactive.
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
