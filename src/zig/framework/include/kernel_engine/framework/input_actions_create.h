#ifndef KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_INPUT_ACTIONS_CREATE_H_

#include <kernel_engine/framework/input_actions.h>
#include <kernel_engine/configuration/configuration.h>

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

    /// [bag] Values a caller gives; a zero field takes its default.
    typedef struct ke_input_actions_config
    {
        /// [borrowed,utf8] The configuration section the maps are read from; NULL reads "input".
        const char *section;
    } ke_input_actions_config;

    /// Creates the action maps, adding through the map's own slots every map the configuration
    /// describes under the section: `<section>.map.<Map>` holds `priority` (default 0) and
    /// `enabled` (default true); `<section>.map.<Map>.action.<Action>` holds `type` (Button,
    /// Axis1D, Axis2D or Axis3D, default Button); `<section>.map.<Map>.action.<Action>.bindings.<n>`
    /// holds `kind` and its keys: `key` for key, `button` (Left, Right, Middle) for mouse,
    /// `negative` and `positive` for key_pair, `up`, `down`, `left` and `right` for key_quad, each
    /// a key name such as "Space" or "W".
    /// @param configuration [borrowed,optional] Read during the call only; NULL creates no map.
    /// @param config [borrowed,optional] NULL takes every default.
    /// @param out_actions [out] Receives the maps; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p out_actions, and for an unknown
    ///         action type, binding kind, key or button name, or a binding missing a key, logging
    ///         where; KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_input_actions_create(
        ke_configuration              *configuration,
        const ke_input_actions_config *config,
        ke_input_actions_handle       *out_actions);

#ifdef __cplusplus
}
#endif

#endif
