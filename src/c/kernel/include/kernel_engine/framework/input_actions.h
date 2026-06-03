#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_

#include <kernel_engine/framework/framework_export.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/input/key.h>
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
        /// Calling load() clears any previously-registered actions (including those
        /// added programmatically via add_action()).
        ke_result (*load)(struct ke_input_actions *self, const char *path);

        /// Resolves an action's string name (the [action.NAME] in the .input file, or
        /// the name passed to add_action()) to its runtime integer id. Returns -1 if
        /// unknown. Callers typically cache the id once after registration and reuse
        /// it across frames.
        int32_t (*get_action_id)(struct ke_input_actions *self, const char *name);

        // ── Programmatic registration ────────────────────────────────────────
        //
        // Bindings can be declared via .input file (load()) or directly via these
        // methods — both routes feed the same internal table and are equivalent
        // at evaluate() time. Action ids are assigned in registration order
        // starting from 0; mixing load() and add_action() is allowed as long as
        // load() is called first.

        /// Registers a new action by name. Returns the assigned action_id (>= 0)
        /// or -1 if name is NULL, empty, or already registered.
        int32_t (*add_action)(struct ke_input_actions *self,
                              const char             *name,
                              ke_action_type          type);

        /// Attaches a single-key Button binding to the action.
        ke_result (*bind_key)(struct ke_input_actions *self,
                              int32_t                  action_id,
                              ke_key                   key);

        /// Attaches a single-mouse-button Button binding to the action.
        ke_result (*bind_mouse_button)(struct ke_input_actions *self,
                                       int32_t                  action_id,
                                       ke_mouse_button          button);

        /// Attaches an Axis1D binding from a key pair: `negative` emits -1,
        /// `positive` emits +1, both held cancels to 0.
        ke_result (*bind_key_pair)(struct ke_input_actions *self,
                                   int32_t                  action_id,
                                   ke_key                   negative,
                                   ke_key                   positive);

        /// Attaches an Axis2D binding from four keys arranged as up/down/left/right.
        /// X = right − left, Y = up − down (matches KeyQuadAxis2DBinding semantics).
        ke_result (*bind_key_quad)(struct ke_input_actions *self,
                                   int32_t                  action_id,
                                   ke_key                   up,
                                   ke_key                   down,
                                   ke_key                   left,
                                   ke_key                   right);

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

    // ── Factory ──────────────────────────────────────────────────────────────

    KE_FRAMEWORK_API ke_result ke_input_actions_create(
        ke_allocator       *alloc,
        ke_input_actions  **out_actions);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_H_
