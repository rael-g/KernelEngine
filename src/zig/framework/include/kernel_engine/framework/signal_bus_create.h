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

    /// Sizing for one signal bus. Each field's default is a convenience, not a
    /// [bag] ceiling.
    typedef struct ke_signal_bus_params
    {
        uint32_t max_signals;      ///< Distinct signal names; 0 uses the default.
        uint32_t max_connections;  ///< Live connections; 0 uses the default.
        uint32_t max_events;       ///< Emissions per frame; 0 uses the default.
        uint32_t max_deliveries;   ///< Joined deliveries per frame; 0 uses the default.
        uint32_t payload_capacity; ///< Total payload bytes per frame; 0 uses the default.
    } ke_signal_bus_params;

    /// Allocates a signal bus. @c params may be NULL to take every default.
    /// @param out_bus [out] Receives the bus; left zeroed on failure.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p out_bus, or
    ///         KE_RESULT_OUT_OF_MEMORY.
    KE_FRAMEWORK_API ke_result ke_signal_bus_create(
        const ke_signal_bus_params *params,
        ke_signal_bus_handle       *out_bus);

#ifdef __cplusplus
}
#endif

#endif
