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

    /** How a field of a config struct is stored. */
    typedef enum ke_config_type
    {
        KE_CONFIG_INT,
        KE_CONFIG_FLOAT,
        KE_CONFIG_DOUBLE,
        KE_CONFIG_BOOL,
        KE_CONFIG_STRING,
    } ke_config_type;

    /** A default of a config field; the member read is the one its type names. */
    typedef union ke_config_value
    {
        int64_t     i;
        double      d;
        bool        b;
        const char *s;
    } ke_config_value;

    /** One field of a config struct: the key naming it, where it lives, and its default. */
    typedef struct ke_config_field
    {
        const char     *key;
        ke_config_type  type;
        uint32_t        offset;
        uint32_t        size;
        ke_config_value default_value;
    } ke_config_field;

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

        /// Fills a config struct: writes each field's default, then the value the store holds for
        /// the field's key in @p section. A key holding a type the field cannot take is logged and
        /// leaves the default; an integer is accepted by a float or double field. A string field
        /// points at the store's copy, valid as get_string's result is.
        /// @param section [borrowed,utf8] The section the struct's keys live in.
        /// @param fields [borrowed,array_of:field_count] The struct's field table.
        /// @param field_count Number of entries in @p fields.
        /// @param out_config [out] The struct to fill.
        /// @return KE_OK, or KE_RESULT_INVALID_ARGUMENT for a null argument or a field whose size
        ///         does not fit its type; fields before it are already written.
        ke_result (*fill)(struct ke_configuration *self, const char *section, const ke_config_field *fields,
                          uint32_t field_count, void *out_config);

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
