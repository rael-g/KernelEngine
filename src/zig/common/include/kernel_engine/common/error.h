#ifndef KERNEL_ENGINE_COMMON_ERROR_H_
#define KERNEL_ENGINE_COMMON_ERROR_H_

#include <stdbool.h>
#include <stdint.h>
#include <kernel_engine/common/common_export.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Error type singleton. ke_error_is() matches a type by address or by name and walks
/// the parent chain; never compare type addresses directly.
///
/// A type's parent is the more generic category it belongs to, or NULL when none fits.
/// ke_error_is() against a category matches every type beneath it, so a caller can match
/// one error exactly or match its whole category.
///
/// Names are dotted and domain-scoped: "ke.<domain>.<...>.<reason>".
typedef struct ke_error_type {
    const char*                  name;    ///< e.g. "ke.window.not_initialized"
    const struct ke_error_type*  parent;  ///< [optional] more generic category, or NULL
} ke_error_type;

/// Rich error context filled by the failing callee via KE_ERROR_SET() / KE_ERROR_WRAP().
/// Points into a thread-local ring buffer — valid until the next two failing calls on the
/// same thread (depth-2 chain is always safe; deeper chains may alias).
typedef struct ke_error {
    const ke_error_type*   type;     ///< [optional] kind of failure
    const char*            message;  ///< [optional] human-readable detail
    const char*            file;     ///< [optional] source file (__FILE__ from KE_ERROR_SET)
    uint32_t               line;     ///< source line (__LINE__ from KE_ERROR_SET)
    const struct ke_error* cause;    ///< [optional] wrapped inner error, or NULL
} ke_error;

/// Generic error type singletons.
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

/// Returns a pointer to the most-recently set error on this thread, or NULL if
/// no error has been set yet. Valid until the next ke_error_set() call on this thread.
KE_COMMON_API const ke_error* ke_error_last(void);

/// Low-level: copies @p message into the calling thread's error slot, fills that slot,
/// and writes its address to *out_error when out_error is non-NULL. @p message and
/// @p file need only outlive this call; the slot owns the copy. Prefer the
/// KE_ERROR_SET / KE_ERROR_WRAP macros, which inject __FILE__ and __LINE__.
KE_COMMON_API void ke_error_set(ke_error** out_error, const ke_error_type* type,
                                const char* message, const char* file, uint32_t line,
                                const ke_error* cause);

/// Record an error at the call site. Statement — must be followed by a return of the
/// appropriate sentinel (NULL, false, KE_ENTITY_INVALID, etc.).
#define KE_ERROR_SET(out_error, type, message) \
    ke_error_set(out_error, type, message, __FILE__, __LINE__, NULL)

/// Like KE_ERROR_SET but chains an inner error as the cause.
#define KE_ERROR_WRAP(out_error, type, message, cause) \
    ke_error_set(out_error, type, message, __FILE__, __LINE__, cause)

/// Prints the full error chain (type name, message, file:line, then each
/// `cause` in turn) to stderr and terminates the process. Does not return.
/// Call it only once no recourse remains for `err`; the engine never calls it itself.
/// It does not raise an OS crash dialog. `err` may be NULL (falls back to a generic message).
KE_COMMON_API _Noreturn void ke_error_fatal(const ke_error* err);

#ifdef __cplusplus
}
#endif

#endif
