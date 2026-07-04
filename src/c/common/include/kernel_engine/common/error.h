#ifndef KERNEL_ENGINE_COMMON_ERROR_H_
#define KERNEL_ENGINE_COMMON_ERROR_H_

#include <stdbool.h>
#include <stdint.h>
#include <kernel_engine/common/common_export.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Error type singleton. Comparison is by identity via ke_error_is(), which walks
/// the parent chain — never compare type addresses directly.
///
/// Error types form an inheritance tree. The generics below (KE_ERROR_*) are the
/// shared roots; it is physically impossible to enumerate every error in existence
/// here, so this header deliberately stays small. Each DOMAIN declares its own,
/// more specific error types as global const instances next to its own API, and
/// points each one's `parent` at a generic root (or another domain type) when the
/// category fits — or leaves `parent` NULL when nothing fits.
///
/// A domain type therefore stays catchable both specifically and by category:
///
///     // in the render domain, beside the GPU device API:
///     const ke_error_type KE_ERROR_GPU_SHADER_COMPILATION = {
///         .name = "ke.render.gpu.shader_compilation", .parent = &KE_ERROR_INVALID_ARGUMENT };
///
///     // a caller can match either the exact type or its whole category:
///     if (ke_error_is(err, &KE_ERROR_GPU_SHADER_COMPILATION)) { ... }   // specific
///     if (ke_error_is(err, &KE_ERROR_INVALID_ARGUMENT))       { ... }   // category
///
/// Names are dotted and domain-scoped: "ke.<domain>.<...>.<reason>".
typedef struct ke_error_type {
    const char*                  name;    ///< e.g. "ke.window.not_initialized"
    const struct ke_error_type*  parent;  ///< more generic category, or NULL
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

/// Returns a pointer to the most-recently set error on this thread, or NULL if
/// no error has been set yet. Valid until the next ke_error_set() call on this thread.
KE_COMMON_API const ke_error* ke_error_last(void);

/// Deep-copies `src` into a heap-owned error that stays valid after the
/// originating thread has moved past its thread-local slots — for carrying an
/// error across a thread boundary (e.g. into an async task's result) or holding
/// it beyond the depth-2 ring. The message and the whole cause chain are copied
/// into owned storage; `type`/`file` are program-lifetime pointers, copied as-is.
/// Returns NULL if `src` is NULL or on allocation failure (never aborts).
/// Release with ke_error_free().
KE_COMMON_API ke_error* ke_error_copy(const ke_error* src);

/// Releases an error returned by ke_error_copy(), including its owned message and
/// cause chain. Must NOT be called on a thread-local error (one from
/// ke_error_last() or written to *out_error by ke_error_set()).
KE_COMMON_API void ke_error_free(ke_error* err);

/// Low-level: fill a thread-local error slot and write to *out_error if non-NULL.
/// Prefer the KE_ERROR_SET / KE_ERROR_WRAP macros which inject __FILE__ and __LINE__.
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
/// `cause` in turn) to stderr and terminates the process.
///
/// This is the engine's only sanctioned "give up and end the program" path.
/// It exists for the caller who has already decided — after a `ke_error`
/// reached them with nowhere left to propagate to — that there is no
/// recourse but to end the process; it is never called automatically inside
/// engine code. Unlike abort()/raise()/__builtin_trap(), it never triggers an
/// OS crash dialog (Windows Error Reporting, Watson, etc.) and always prints
/// a readable message before exiting, matching the "never silent" doctrine.
/// `err` may be NULL (falls back to a generic message). Does not return.
KE_COMMON_API _Noreturn void ke_error_fatal(const ke_error* err);

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_COMMON_ERROR_H_
