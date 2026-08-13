#ifndef KERNEL_ENGINE_FRAMEWORK_SIGNAL_BUS_CREATE_H_
#define KERNEL_ENGINE_FRAMEWORK_SIGNAL_BUS_CREATE_H_

#include <kernel_engine/framework/signal_bus.h>

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

    /// Sizing for one signal bus. Every field is a workload shape, not a law:
    /// how many distinct signals a game declares, how many wires it draws, and
    /// how much traffic one frame carries are the game's business, so exceeding
    /// a default is a reason to raise it rather than a ceiling to design around.
    typedef struct ke_signal_bus_params
    {
        uint32_t max_signals;      ///< Distinct signal names; 0 uses the default.
        uint32_t max_connections;  ///< Live connections; 0 uses the default.
        uint32_t max_events;       ///< Emissions per frame; 0 uses the default.
        uint32_t max_deliveries;   ///< Joined deliveries per frame; 0 uses the default.
        uint32_t payload_capacity; ///< Total payload bytes per frame; 0 uses the default.
    } ke_signal_bus_params;

    /// Allocates a signal bus. @c params may be NULL to take every default.
    /// @return Handle whose @c ref is NULL on failure.
    KE_FRAMEWORK_API ke_signal_bus_handle ke_signal_bus_create(
        const ke_signal_bus_params *params,
        ke_error                  **out_error);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SIGNAL_BUS_CREATE_H_
