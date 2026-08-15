#ifndef KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_H_
#define KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_H_

#include <kernel_engine/common/error.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint32_t ke_configuration_subscription;

#define KE_CONFIGURATION_SUBSCRIPTION_NONE UINT32_MAX

    /// Change callback: invoked with the section whose value(s) changed, plus the
    /// unchanged ctx supplied at subscribe time. Latch-only — see doctrine above.
    typedef void (*ke_configuration_change_func)(const char *section, void *ctx);

    typedef struct ke_configuration
    {
        void *handle;

        int64_t (*get_int)(struct ke_configuration *self, const char *section, const char *key, int64_t fallback);
        double (*get_double)(struct ke_configuration *self, const char *section, const char *key, double fallback);
        bool (*get_bool)(struct ke_configuration *self, const char *section, const char *key, bool fallback);
        /// Returned pointer is owned by the store and valid until the same key is
        /// overwritten or the store is destroyed. Copy it if you need to retain.
        const char *(*get_string)(struct ke_configuration *self, const char *section, const char *key, const char *fallback);

        bool (*set_int)(struct ke_configuration *self, const char *section, const char *key, int64_t value, ke_error **out_error);
        bool (*set_double)(struct ke_configuration *self, const char *section, const char *key, double value, ke_error **out_error);
        bool (*set_bool)(struct ke_configuration *self, const char *section, const char *key, bool value, ke_error **out_error);
        bool (*set_string)(struct ke_configuration *self, const char *section, const char *key, const char *value, ke_error **out_error);

        /// Subscribes to writes on `section`. Returns a subscription id, or
        /// KE_CONFIGURATION_SUBSCRIPTION_NONE on failure.
        ke_configuration_subscription (*subscribe)(struct ke_configuration *self,
                                                   const char                  *section,
                                                   ke_configuration_change_func cb,
                                                   void                        *ctx);

        /// Removes a subscription. Safe to call with KE_CONFIGURATION_SUBSCRIPTION_NONE.
        void (*unsubscribe)(struct ke_configuration *self, ke_configuration_subscription sub);

    } ke_configuration;

    typedef struct ke_configuration_handle
    {
        ke_configuration *ref;
        void (*destroy)(ke_configuration *self);
    } ke_configuration_handle;

#ifdef __cplusplus
}
#endif

#endif
