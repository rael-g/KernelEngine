#ifndef KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_H_
#define KERNEL_ENGINE_CONFIGURATION_CONFIGURATION_H_

#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <stddef.h>
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

    /** How a field of a config struct is stored. */
    typedef enum ke_config_type
    {
        KE_CONFIG_INT,
        KE_CONFIG_FLOAT,
        KE_CONFIG_DOUBLE,
        KE_CONFIG_BOOL,
        KE_CONFIG_STRING,
    } ke_config_type;

    /** One field of a config struct: the key naming it, where it lives and how it is stored. */
    typedef struct ke_config_field
    {
        const char     *key;
        /// A float field larger than one float is a vector, read element by element from the
        /// keys `<key>.0`, `<key>.1`, and so on.
        ke_config_type  type;
        uint32_t        offset;
        uint32_t        size;
        /// [borrowed,optional,array_of:enum_count] The names an integer field's key may hold, in
        /// value order; a name stands for its index. NULL leaves the field numeric.
        const char *const *enum_names;
        uint32_t           enum_count;
    } ke_config_field;

/** The ke_config_type of member @p m of config struct @p T, taken from the member's own type. */
#define KE_CONFIG_TYPE_OF(T, m) _Generic(((T *)0)->m, \
    _Bool: KE_CONFIG_BOOL, \
    signed char: KE_CONFIG_INT, short: KE_CONFIG_INT, int: KE_CONFIG_INT, long: KE_CONFIG_INT, long long: KE_CONFIG_INT, \
    unsigned char: KE_CONFIG_INT, unsigned short: KE_CONFIG_INT, unsigned int: KE_CONFIG_INT, unsigned long: KE_CONFIG_INT, unsigned long long: KE_CONFIG_INT, \
    float: KE_CONFIG_FLOAT, double: KE_CONFIG_DOUBLE, \
    char *: KE_CONFIG_STRING, const char *: KE_CONFIG_STRING)

/** The field-table entry of member @p m of config struct @p T, keyed by the member's name. */
#define KE_CONFIG_FIELD(T, m) { #m, KE_CONFIG_TYPE_OF(T, m), (uint32_t)offsetof(T, m), (uint32_t)sizeof(((T *)0)->m), NULL, 0 }

/** The field-table entry of an enum member @p m of @p T whose key may hold one of @p names. */
#define KE_CONFIG_ENUM_FIELD(T, m, names) { #m, KE_CONFIG_INT, (uint32_t)offsetof(T, m), (uint32_t)sizeof(((T *)0)->m), (names), (uint32_t)(sizeof(names) / sizeof((names)[0])) }

/** The field-table entry of a member @p m of @p T made of floats, such as a vector, read element by element. */
#define KE_CONFIG_VECTOR_FIELD(T, m) { #m, KE_CONFIG_FLOAT, (uint32_t)offsetof(T, m), (uint32_t)sizeof(((T *)0)->m), NULL, 0 }

/** Expands a field table into the `fields` and `field_count` arguments of ke_configuration.fill. */
#define KE_CONFIG_FIELDS(table) (table), (uint32_t)(sizeof(table) / sizeof((table)[0]))

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

        /// Writes into @p config the value the store holds for each field's key in @p section; a
        /// field whose key the store does not hold keeps what @p config held, so a caller starts
        /// from the struct's defaults. A key holding a type the field cannot take is logged and
        /// leaves the field; an integer is accepted by a float or double field, and a name from
        /// the field's enum names by an integer field. A string field points at the store's copy,
        /// valid as get_string's result is.
        /// @param section [borrowed,utf8] The section the struct's keys live in.
        /// @param fields [borrowed,array_of:field_count] The struct's field table.
        /// @param field_count Number of entries in @p fields.
        /// @param config [borrowed] The struct to fill.
        /// @return KE_OK, or KE_RESULT_INVALID_ARGUMENT for a null argument or a field whose size
        ///         does not fit its type; fields before it are already written.
        ke_result (*fill)(struct ke_configuration *self, const char *section, const ke_config_field *fields,
                          uint32_t field_count, void *config);

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
