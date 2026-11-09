#ifndef KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_H_
#define KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_H_

#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef uint32_t ke_configuration_subscription;

#define KE_CONFIGURATION_SUBSCRIPTION_NONE UINT32_MAX

    /// Change callback: invoked with the section whose value(s) changed, plus the
    /// ctx supplied at subscribe time, passed back unchanged. The callback must be
    /// latch-only: it records that the section changed and does nothing else.
    typedef void (*ke_configuration_change_func)(const char *section, void *ctx);

    /** Receives one child section of the section being listed.
     * @param name [borrowed,utf8] The child's own name, without its parent's; valid only during the call.
     * @param ctx [context] Opaque context forwarded from the call that listed. */
    typedef void (*ke_configuration_child_func)(const char *name, void *ctx);

    /** [interface] A typed (section, key) to value store. */
    typedef struct ke_configuration
    {
        void *handle;

        int64_t (*get_int)(struct ke_configuration *self, const char *section, const char *key, int64_t fallback);
        double (*get_double)(struct ke_configuration *self, const char *section, const char *key, double fallback);
        bool (*get_bool)(struct ke_configuration *self, const char *section, const char *key, bool fallback);
        /// Returned pointer is owned by the store and valid until the same key is
        /// overwritten or the store is destroyed. Copy it if you need to retain.
        const char *(*get_string)(struct ke_configuration *self, const char *section, const char *key, const char *fallback);

        /// Stores @p value under @p section and @p key, replacing what the key held, then runs the
        /// section's subscribers. Returns KE_RESULT_INVALID_ARGUMENT for a null section or key and
        /// KE_RESULT_OUT_OF_MEMORY when the entry cannot be stored; the store is then unchanged.
        ke_result (*set_int)(struct ke_configuration *self, const char *section, const char *key, int64_t value);
        /// As set_int, for a double.
        ke_result (*set_double)(struct ke_configuration *self, const char *section, const char *key, double value);
        /// As set_int, for a boolean.
        ke_result (*set_bool)(struct ke_configuration *self, const char *section, const char *key, bool value);
        /// As set_int, for a string, copied; a null value is also an invalid argument.
        ke_result (*set_string)(struct ke_configuration *self, const char *section, const char *key, const char *value);

        /// Subscribes to writes on `section`. Returns a subscription id, or
        /// KE_CONFIGURATION_SUBSCRIPTION_NONE on failure.
        ke_configuration_subscription (*subscribe)(struct ke_configuration *self,
                                                   const char                  *section,
                                                   ke_configuration_change_func cb,
                                                   void                        *ctx);

        /// Removes a subscription. Safe to call with KE_CONFIGURATION_SUBSCRIPTION_NONE.
        void (*unsubscribe)(struct ke_configuration *self, ke_configuration_subscription sub);

        /// Lists the sections directly under @p section, once each, in the order their first key
        /// was stored. A section is under another when its name is the other's followed by a dot
        /// and one more name; it is listed when it or any section under it holds a key.
        /// @param section [borrowed,utf8] The parent; "" lists the top-level sections.
        /// @param each [closure:ctx] Called once per child section.
        /// @return KE_OK, or KE_RESULT_INVALID_ARGUMENT for a null section or callback.
        ke_result (*for_each_child)(struct ke_configuration *self, const char *section,
                                    ke_configuration_child_func each, void *ctx);

    } ke_configuration;

    /// [owner]
    typedef struct ke_configuration_handle
    {
        ke_configuration *ref;
        void (*destroy)(ke_configuration *self);
    } ke_configuration_handle;

#ifdef __cplusplus
}
#endif

#endif
