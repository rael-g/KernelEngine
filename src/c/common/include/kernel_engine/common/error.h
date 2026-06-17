#ifndef KERNEL_ENGINE_COMMON_ERROR_H_
#define KERNEL_ENGINE_COMMON_ERROR_H_

#include <stdbool.h>
#include <kernel_engine/common/common_export.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Two-value result: KE_OK (success) or KE_ERROR (failure).
/// Rich context is carried by ke_error — see ke_error_is() and ke_error_set().
typedef enum ke_result { KE_OK = 0, KE_ERROR = -1 } ke_result;

/// Error type singleton. Each domain declares its types as global const instances.
/// Comparison is by pointer identity via ke_error_is() — never compare addresses directly.
typedef struct ke_error_type {
    const char*                  name;    ///< e.g. "ke.window.not_initialized"
    const struct ke_error_type*  parent;  ///< generic category, or NULL
} ke_error_type;

/// Rich error context filled by the failing callee via ke_error_set().
/// Points into a thread-local buffer — valid until the next failing call on the same thread.
typedef struct ke_error {
    const ke_error_type* type;
    const char*          message;  ///< human-readable detail
    const char*          domain;   ///< e.g. "ke_window"
} ke_error;

/// Generic error type singletons (defined in error.c, exported from ke_common.dll).
KE_COMMON_API extern const ke_error_type KE_ERROR_GENERAL;
KE_COMMON_API extern const ke_error_type KE_ERROR_NOT_FOUND;
KE_COMMON_API extern const ke_error_type KE_ERROR_IO;
KE_COMMON_API extern const ke_error_type KE_ERROR_OUT_OF_MEMORY;
KE_COMMON_API extern const ke_error_type KE_ERROR_INVALID_ARGUMENT;
KE_COMMON_API extern const ke_error_type KE_ERROR_NOT_INITIALIZED;
KE_COMMON_API extern const ke_error_type KE_ERROR_NOT_SUPPORTED;
KE_COMMON_API extern const ke_error_type KE_ERROR_ALREADY_EXISTS;

/// Returns true if err->type matches type or any ancestor in its parent chain.
KE_COMMON_API bool ke_error_is(const ke_error* err, const ke_error_type* type);

/// Fill the thread-local error slot, point *out_error at it (if non-NULL), and return KE_ERROR.
KE_COMMON_API ke_result ke_error_set(ke_error** out_error, const ke_error_type* type,
                                     const char* domain, const char* message);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_COMMON_ERROR_H_
