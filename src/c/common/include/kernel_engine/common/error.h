#ifndef KERNEL_ENGINE_COMMON_ERROR_H_
#define KERNEL_ENGINE_COMMON_ERROR_H_

#include <stdbool.h>
#include <stdint.h>
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

/// Rich error context filled by the failing callee via KE_ERROR_SET() / KE_ERROR_WRAP().
/// Points into a thread-local ring buffer — valid until the next two failing calls on the
/// same thread (depth-2 chain is always safe; deeper chains may alias).
typedef struct ke_error {
    const ke_error_type*   type;
    const char*            message;  ///< human-readable detail
    const char*            file;     ///< source file (__FILE__ from KE_ERROR_SET)
    uint32_t               line;     ///< source line (__LINE__ from KE_ERROR_SET)
    const struct ke_error* cause;    ///< wrapped inner error, or NULL
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

/// Low-level: fill a thread-local error slot and return KE_ERROR.
/// Prefer the KE_ERROR_SET / KE_ERROR_WRAP macros which inject __FILE__ and __LINE__.
KE_COMMON_API ke_result ke_error_set(ke_error** out_error, const ke_error_type* type,
                                     const char* message, const char* file, uint32_t line,
                                     const ke_error* cause);

/// Report an error at the call site. Expands to a ke_error_set() call with __FILE__/__LINE__
/// already filled; evaluates to KE_ERROR so it can be used as a return statement.
#define KE_ERROR_SET(out_error, type, message) \
    ke_error_set(out_error, type, message, __FILE__, __LINE__, NULL)

/// Like KE_ERROR_SET but chains an inner error as the cause.
#define KE_ERROR_WRAP(out_error, type, message, cause) \
    ke_error_set(out_error, type, message, __FILE__, __LINE__, cause)

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_COMMON_ERROR_H_
