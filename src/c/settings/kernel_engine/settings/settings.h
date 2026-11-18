#ifndef KERNEL_ENGINE_SETTINGS_SETTINGS_H_
#define KERNEL_ENGINE_SETTINGS_SETTINGS_H_

#include <kernel_engine/result/result.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ke_settings ke_settings;

/// Receives one key the settings hold.
/// @param key [borrowed,utf8] The key; valid only during the call.
/// @param ctx [context] Forwarded from for_each_key.
typedef void (*ke_settings_key_func)(const char *key, void *ctx);

/// [lent] The values one part is created with, each under a key and of one type. A part reads
/// them once, when it is created; a value that changes afterwards is a slot of the part's own
/// contract.
typedef struct ke_settings {
    void *handle;

    /// Reads a boolean.
    /// @param key [utf8] The key.
    /// @param out_value [out] Receives the value; untouched on failure.
    /// @return KE_OK; KE_RESULT_NOT_FOUND when no value is under @p key; KE_RESULT_INVALID_ARGUMENT
    ///         for a null argument or when the value under @p key is of another type.
    ke_result (*get_bool)(ke_settings *self, const char *key, bool *out_value);

    /// Reads an integer, as get_bool.
    /// @param key [utf8] The key.
    /// @param out_value [out] Receives the value; untouched on failure.
    ke_result (*get_int)(ke_settings *self, const char *key, int64_t *out_value);

    /// Reads a floating-point number, as get_bool. An integer value is read as its number.
    /// @param key [utf8] The key.
    /// @param out_value [out] Receives the value; untouched on failure.
    ke_result (*get_double)(ke_settings *self, const char *key, double *out_value);

    /// Reads a string, as get_bool.
    /// @param key [utf8] The key.
    /// @param out_value [out,utf8] Receives the string, borrowed while the settings live and the key is
    ///        not written again.
    ke_result (*get_string)(ke_settings *self, const char *key, const char **out_value);

    /// Calls @p each once for every key that holds a value, in no particular order.
    /// @param each [closure:ctx] Called once per key.
    /// @return KE_OK, or KE_RESULT_INVALID_ARGUMENT for a null @p each.
    ke_result (*for_each_key)(ke_settings *self, ke_settings_key_func each, void *ctx);
} ke_settings;

#ifdef __cplusplus
}
#endif

#endif
