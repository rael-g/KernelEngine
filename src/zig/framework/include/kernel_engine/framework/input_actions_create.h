#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_

#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/settings/settings.h>

#ifdef __cplusplus
extern "C"
{
#endif

#ifndef KE_FRAMEWORK_API
#if defined(_WIN32) || defined(__CYGWIN__)
#ifdef KE_FRAMEWORK_STATIC
#define KE_FRAMEWORK_API
#else
#ifdef KE_FRAMEWORK_EXPORT
#define KE_FRAMEWORK_API __declspec(dllexport)
#else
#define KE_FRAMEWORK_API __declspec(dllimport)
#endif
#endif
#else
#define KE_FRAMEWORK_API __attribute__((visibility("default")))
#endif
#endif

    /// Creates the action maps, adding through the map's own slots every map @p settings describe:
    /// the child `map.<Map>` holds `priority` (default 0) and `enabled` (default true);
    /// `map.<Map>.action.<Action>` holds `type` (Button, Axis1D, Axis2D or Axis3D, default Button);
    /// `map.<Map>.action.<Action>.bindings.<n>` holds `kind` and its keys: `key` for key, `button`
    /// (Left, Right, Middle) for mouse, `negative` and `positive` for key_pair, `up`, `down`, `left`
    /// and `right` for key_quad, each a key name such as "Space" or "W".
    /// The input actions module evaluates the maps each tick.
    /// @param settings [borrowed] Read once; holds no key and no child but `map`.
    /// @param out_actions [out] Receives the maps; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument, a key or a child the settings
    ///         do not hold, an unknown action type, binding kind, key or button name, or a binding
    ///         missing a key, logging where; KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_input_actions_create(
        ke_settings                   *settings,
        ke_input_actions_handle       *out_actions);

#ifdef __cplusplus
}
#endif

#endif
